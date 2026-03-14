# frozen_string_literal: true

require_relative "../shared/json_extractor"
require_relative "../shared/muscle_group_mapper"
require_relative "../shared/exercise_finder"

module AiTrainer
  module DynamicRoutine
    # Parses AI JSON response and enriches exercises with YouTube knowledge.
    # Depends on host class providing: @level
    module ResponseParser
      include Shared::JsonExtractor
      include Shared::MuscleGroupMapper
      include Shared::ExerciseFinder

      def parse_ai_response(response, available_exercises)
        json_match = response.match(/```json\s*(.*?)\s*```/m) || response.match(/\{.*\}/m)
        raise "AI 응답에서 JSON을 찾을 수 없습니다" unless json_match

        json_str = json_match[1] || json_match[0]
        data = JSON.parse(json_str, symbolize_names: true)

        exercise_lookup = available_exercises.index_by(&:id)

        exercises = data[:exercises].map.with_index(1) do |ex, order|
          db_exercise = exercise_lookup[ex[:exercise_id].to_i]

          {
            order: order,
            exercise_id: ex[:exercise_id],
            exercise_name: ex[:exercise_name] || db_exercise&.name,
            english_name: db_exercise&.english_name,
            target_muscle: db_exercise&.muscle_group,
            sets: ex[:sets],
            reps: ex[:reps],
            target_total_reps: ex[:target_total_reps],
            weight_description: ex[:weight_description],
            bpm: ex[:bpm],
            range_of_motion: ex[:rom] || "full",
            work_seconds: ex[:work_seconds],
            rest_seconds: ex[:rest_seconds] || 60,
            rest_type: ex[:work_seconds] ? "tabata" : "time_based",
            training_method: ex[:training_method] || "standard",
            instructions: ex[:instructions],
            form_tips: db_exercise&.form_tips,
            common_mistakes: db_exercise&.common_mistakes
          }
        end

        {
          exercises: exercises,
          warmup_suggestion: data[:warmup_suggestion],
          cooldown_suggestion: data[:cooldown_suggestion],
          coach_note: data[:coach_note]
        }
      end

      # Enrich exercises with YouTube/RAG knowledge
      def enrich_with_knowledge(routine)
        return routine unless rag_available?

        exercise_names = routine[:exercises].map { |ex| ex[:english_name] }.compact
        muscle_groups = routine[:exercises].map { |ex| ex[:target_muscle] }.compact.uniq

        begin
          contextual_knowledge = RagSearchService.contextual_search(
            exercises: exercise_names,
            muscle_groups: muscle_groups,
            knowledge_types: %w[exercise_technique form_check],
            difficulty_level: difficulty_for_level(@level),
            limit: 15
          )

          routine[:exercises] = routine[:exercises].map { |ex| enrich_exercise(ex, contextual_knowledge) }
        rescue StandardError => e
          Rails.logger.warn("Knowledge enrichment failed: #{e.message}")
        end

        routine
      end

      private

      def rag_available?
        defined?(RagSearchService) && defined?(FitnessKnowledgeChunk)
      end

      def difficulty_for_level(level)
        case level
        when 1..2 then "beginner"
        when 3..5 then "intermediate"
        when 6..8 then "advanced"
        else "intermediate"
        end
      end

      def enrich_exercise(exercise, contextual_knowledge)
        target_name = exercise[:english_name]&.downcase
        target_muscle = exercise[:target_muscle]&.downcase

        exercise_matches = contextual_knowledge.select do |k|
          exercise_names = k[:exercise_name]&.downcase&.split(", ") || []
          exercise_names.include?(target_name) || k[:exercise_name]&.downcase == target_name
        end

        relevant = exercise_matches.presence || contextual_knowledge.select do |k|
          k[:muscle_group]&.downcase == target_muscle
        end

        if relevant.present?
          tips = relevant.first(2).map { |k| k[:summary] }.compact
          sources = relevant.first(2).filter_map do |k|
            next unless k[:source]

            { title: k[:summary] || k[:source][:video_title], url: k[:source][:video_url], channel: k[:source][:channel_name] }
          end

          exercise[:expert_tips] = tips if tips.present?
          exercise[:video_references] = sources if sources.present?
        end

        exercise
      end
    end
  end
end
