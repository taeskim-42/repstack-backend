# frozen_string_literal: true

# Enrich routine exercises with RAG knowledge (YouTube links, expert tips, form cues).
# Used by Internal API to add fitness knowledge to DB-stored routines on-the-fly.
class RoutineEnrichmentService
  class << self
    def enrich(exercises, user_level: nil)
      return exercises unless rag_available?
      return exercises if exercises.blank?

      exercise_names = exercises.map { |ex| ex[:exercise_name] }.compact
      muscle_groups = exercises.map { |ex| ex[:target_muscle] }.compact.uniq

      # Batch fetch knowledge for all exercises
      chunks = fetch_knowledge(exercise_names, muscle_groups, user_level)
      return exercises if chunks.empty?

      exercises.map { |ex| enrich_exercise(ex, chunks) }
    rescue StandardError => e
      Rails.logger.warn("[RoutineEnrichment] Failed: #{e.message}")
      exercises
    end

    private

    def rag_available?
      FitnessKnowledgeChunk.table_exists? && FitnessKnowledgeChunk.any?
    rescue StandardError
      false
    end

    def fetch_knowledge(exercise_names, muscle_groups, user_level)
      difficulty = case user_level.to_i
                   when 1..2 then "beginner"
                   when 3..5 then "intermediate"
                   when 6..10 then "advanced"
                   end

      RagSearchService.contextual_search(
        exercises: exercise_names,
        muscle_groups: muscle_groups,
        knowledge_types: %w[exercise_technique form_check],
        difficulty_level: difficulty,
        limit: 20
      )
    end

    def enrich_exercise(exercise, all_chunks)
      name = exercise[:exercise_name].to_s.downcase
      muscle = exercise[:target_muscle].to_s.downcase

      # Find chunks relevant to this specific exercise
      relevant = all_chunks.select do |chunk|
        chunk_name = (chunk[:exercise_name] || "").downcase
        chunk_muscle = (chunk[:muscle_group] || "").downcase
        chunk_content = (chunk[:content] || "").downcase

        chunk_name.include?(name) || name.include?(chunk_name) ||
          chunk_content.include?(name) ||
          (chunk_muscle.present? && chunk_muscle.include?(muscle))
      end

      return exercise if relevant.empty?

      tips = []
      form_cues = []
      video_refs = []

      relevant.first(4).each do |chunk|
        case chunk[:type]
        when "exercise_technique"
          tip = extract_tip(chunk[:content], chunk[:summary])
          tips << tip if tip.present?
        when "form_check"
          cue = extract_form_cue(chunk[:content], chunk[:summary])
          form_cues << cue if cue.present?
        end

        if chunk[:source].present? && chunk[:source][:video_url].present?
          video_refs << {
            title: chunk[:summary] || chunk[:source][:video_title],
            url: chunk[:source][:video_url],
            channel: chunk[:source][:channel_name]
          }
        end
      end

      exercise[:expert_tips] = tips.uniq.first(3) if tips.any?
      exercise[:form_cues] = form_cues.uniq.first(2) if form_cues.any?
      exercise[:video_references] = video_refs.uniq { |v| v[:url] }.first(2) if video_refs.any?

      # Enrich instructions with tips
      if exercise[:instructions].blank? || too_simple?(exercise[:instructions])
        parts = [exercise[:instructions]].compact
        parts << "💡 #{tips.first}" if tips.any?
        parts << "✅ #{form_cues.first}" if form_cues.any?
        exercise[:instructions] = parts.join("\n") if parts.length > 1
      end

      exercise
    end

    def extract_tip(content, summary)
      return summary if summary.present? && summary.length.between?(10, 100)

      sentences = content.to_s.split(/[.!?。]/).map(&:strip).reject(&:empty?)
      sentences.find { |s| s.length.between?(20, 150) } || summary&.truncate(100)
    end

    def extract_form_cue(content, summary)
      return summary if summary.present? && summary.length.between?(10, 100)

      content.to_s.split(/[.!?。]/).find do |s|
        s.match?(/자세|폼|각도|호흡|팔꿈치|무릎|허리|어깨|코어|등|가슴|form|posture/i)
      end&.strip&.truncate(100)
    end

    def too_simple?(text)
      text.to_s.length < 20
    end
  end
end
