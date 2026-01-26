# frozen_string_literal: true

# RAG (Retrieval Augmented Generation) Search Service
# Retrieves relevant fitness knowledge to enhance AI Trainer responses
class RagSearchService
  class << self
    # Main search method - combines vector and keyword search
    def search(query, limit: 5, knowledge_types: nil, filters: {})
      return [] if query.blank?

      # Try vector search first if available
      results = if EmbeddingService.pgvector_available? && EmbeddingService.configured?
        vector_search(query, limit: limit, knowledge_types: knowledge_types, filters: filters)
      else
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
    def contextual_search(exercises: [], muscle_groups: [], goals: [], knowledge_types: nil, difficulty_level: nil, limit: 10)
      exercise_names = exercises
      goals = goals
      difficulty = difficulty_level

      # Combine different search strategies
      results = []

      # 1. Direct exercise matches
      if exercise_names.present?
        scope = FitnessKnowledgeChunk.relevant_for_context(
          exercise_names: exercise_names,
          limit: limit / 2
        )
        scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?
        results += scope.to_a
      end

      # 2. Muscle group matches
      if muscle_groups.present?
        scope = FitnessKnowledgeChunk.relevant_for_context(
          muscle_groups: muscle_groups,
          limit: limit / 3
        )
        scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?
        results += scope.to_a
      end

      # 3. Goal-based search (nutrition for weight loss, etc.)
      if goals.include?("weight_loss") || goals.include?("fat_loss")
        results += FitnessKnowledgeChunk.nutrition_recovery.limit(2).to_a
      end

      # Filter by difficulty if specified
      if difficulty.present?
        results.select! { |r| r.difficulty_level.nil? || r.difficulty_level == difficulty }
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

    def vector_search(query, limit:, knowledge_types:, filters:)
      embedding = EmbeddingService.generate_query_embedding(query)
      return keyword_search(query, limit: limit, knowledge_types: knowledge_types, filters: filters) unless embedding

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
