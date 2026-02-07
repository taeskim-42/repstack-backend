# frozen_string_literal: true

# RAG (Retrieval Augmented Generation) Search Service
# Retrieves relevant fitness knowledge to enhance AI Trainer responses
class RagSearchService
  class << self
    # Main search method - uses hybrid search (vector + keyword) for best results
    def search(query, limit: 5, knowledge_types: nil, filters: {})
      return [] if query.blank?

      results = if EmbeddingService.pgvector_available? && EmbeddingService.configured?
        # Hybrid search: combine vector (semantic) + keyword (exact match)
        hybrid_search(query, limit: limit, knowledge_types: knowledge_types, filters: filters)
      else
        # Fallback to keyword-only when vector search unavailable
        keyword_search(query, limit: limit, knowledge_types: knowledge_types, filters: filters)
      end

      format_results(results)
    end

    # Search for knowledge relevant to a specific exercise
    def search_for_exercise(exercise_name, knowledge_types: nil, limit: 5)
      scope = FitnessKnowledgeChunk.for_exercise(exercise_name)
      scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?

      format_results(scope.limit(limit))
    end

    # Search for knowledge relevant to a muscle group
    def search_for_muscle_group(muscle_group, knowledge_types: nil, limit: 5)
      scope = FitnessKnowledgeChunk.for_muscle_group(muscle_group)
      scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?

      format_results(scope.limit(limit))
    end

    # Get knowledge for user's current context (workout, exercises, goals)
    # difficulty_level: "beginner", "intermediate", or "advanced"
    def contextual_search(exercises: [], muscle_groups: [], goals: [], knowledge_types: nil, difficulty_level: nil, limit: 10)
      exercise_names = exercises
      goals = goals

      # Base scope with level filtering (beginner gets beginner+all, etc.)
      base_scope = if difficulty_level.present?
        FitnessKnowledgeChunk.for_level(difficulty_level)
      else
        FitnessKnowledgeChunk.all
      end

      # Combine different search strategies
      results = []

      # 1. Direct exercise matches (PRIORITY - only use these if found)
      if exercise_names.present?
        scope = base_scope.relevant_for_context(
          exercise_names: exercise_names,
          limit: limit
        )
        scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?
        results += scope.to_a
      end

      # 2. Muscle group matches - ONLY if no exercise matches found
      # This prevents unrelated videos from being included when we have exact matches
      if results.empty? && muscle_groups.present?
        scope = base_scope.relevant_for_context(
          muscle_groups: muscle_groups,
          limit: limit / 2
        )
        scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?
        results += scope.to_a
      end

      # 3. Goal-based search (nutrition for weight loss, etc.)
      if goals.include?("weight_loss") || goals.include?("fat_loss")
        results += base_scope.nutrition_recovery.limit(2).to_a
      end

      # Deduplicate and limit
      format_results(results.uniq.first(limit))
    end

    # Build prompt context from knowledge chunks for AI Trainer
    def build_context_prompt(chunks)
      return "" if chunks.empty?

      context_parts = chunks.map do |chunk|
        build_chunk_prompt(chunk)
      end

      <<~PROMPT
        ## 참고 지식 (YouTube 전문 피트니스 채널에서 수집)

        #{context_parts.join("\n\n")}

        위 정보를 참고하여 답변하되, 출처를 직접 언급하지 마세요.
      PROMPT
    end

    # Batch search: combine multiple keywords into fewer queries.
    # Instead of N separate hybrid_search calls, joins keywords for 1 vector + 1 keyword search.
    def batch_search(keywords, limit: 5)
      return [] if keywords.blank?

      combined_query = keywords.first(5).join(" ")

      results = if EmbeddingService.pgvector_available? && EmbeddingService.configured?
        hybrid_search(combined_query, limit: limit, knowledge_types: nil, filters: {})
      else
        keyword_search(combined_query, limit: limit, knowledge_types: nil, filters: {})
      end

      format_results(results)
    end

    # Get trending/popular knowledge (most referenced)
    def trending_knowledge(limit: 5)
      FitnessKnowledgeChunk
        .joins(:youtube_video)
        .where("youtube_videos.view_count > ?", 10_000)
        .order("youtube_videos.view_count DESC")
        .limit(limit)
        .then { |r| format_results(r) }
    end

    private

    # Hybrid search: combines vector (semantic) and keyword (exact match) results
    # - Vector search finds semantically similar content
    # - Keyword search finds exact term matches
    # - Combining both improves recall and precision
    def hybrid_search(query, limit:, knowledge_types:, filters:)
      # Split limit between vector and keyword (60/40 favoring semantic)
      vector_limit = (limit * 0.6).ceil
      keyword_limit = (limit * 0.4).ceil

      # Get results from both search methods
      vector_results = vector_search(query, limit: vector_limit, knowledge_types: knowledge_types, filters: filters)
      keyword_results = keyword_search(query, limit: keyword_limit, knowledge_types: knowledge_types, filters: filters)

      # Merge and deduplicate, prioritizing vector results (semantic relevance)
      seen_ids = Set.new
      combined = []

      # Add vector results first (higher priority)
      vector_results.each do |chunk|
        next if seen_ids.include?(chunk.id)
        seen_ids.add(chunk.id)
        combined << chunk
      end

      # Add keyword results that weren't in vector results
      keyword_results.each do |chunk|
        next if seen_ids.include?(chunk.id)
        seen_ids.add(chunk.id)
        combined << chunk
        break if combined.size >= limit
      end

      combined.first(limit)
    end

    def vector_search(query, limit:, knowledge_types:, filters:)
      embedding = EmbeddingService.generate_query_embedding(query)
      return keyword_search(query, limit: limit, knowledge_types: knowledge_types, filters: filters) unless embedding

      # IVFFlat 인덱스 정확도 향상을 위해 probes 값 설정
      # 기본값(1)이 너무 낮아 관련 결과 누락됨, 20으로 설정하여 검색 품질 개선
      ActiveRecord::Base.connection.execute("SET ivfflat.probes = 20")

      scope = FitnessKnowledgeChunk.with_embedding
      scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?
      scope = apply_filters(scope, filters)

      scope.nearest_neighbors(:embedding, embedding, distance: "cosine").limit(limit)
    end

    def keyword_search(query, limit:, knowledge_types:, filters:)
      scope = FitnessKnowledgeChunk.keyword_search(query, limit: limit * 2)
      scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?
      scope = apply_filters(scope, filters)

      scope.limit(limit)
    end

    def apply_filters(scope, filters)
      scope = scope.where(exercise_name: filters[:exercise_name]) if filters[:exercise_name].present?
      scope = scope.where(muscle_group: filters[:muscle_group]) if filters[:muscle_group].present?
      scope = scope.where(difficulty_level: filters[:difficulty_level]) if filters[:difficulty_level].present?
      scope
    end

    def format_results(chunks)
      chunks.map do |chunk|
        {
          id: chunk.id,
          type: chunk.knowledge_type,
          content: chunk.content,
          summary: chunk.summary,
          exercise_name: chunk.exercise_name,
          muscle_group: chunk.muscle_group,
          difficulty_level: chunk.difficulty_level,
          source: chunk.source_reference
        }
      end
    end

    def build_chunk_prompt(chunk)
      parts = []
      parts << "### #{chunk[:summary] || chunk[:type].humanize}"
      parts << chunk[:content]

      if chunk[:exercise_name]
        parts << "운동: #{chunk[:exercise_name]}"
      end

      if chunk[:muscle_group]
        parts << "부위: #{chunk[:muscle_group]}"
      end

      parts.join("\n")
    end
  end
end
