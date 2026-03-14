# frozen_string_literal: true

require_relative "../shared/json_extractor"
require_relative "../shared/exercise_finder"

module AiTrainer
  module CreativeRoutine
    # Parses LLM JSON response into structured routine hash.
    # Depends on host class providing: @level, @day_of_week, @goal
    module ResponseParser
      include Shared::JsonExtractor
      include Shared::ExerciseFinder

      def parse_routine_response(content)
        json_str = extract_json(content)
        data = JSON.parse(json_str)

        exercises = data["exercises"].map.with_index(1) do |ex, idx|
          exercise_name = ex["name"] || "운동 #{idx}"
          db_exercise = find_exercise_by_name(exercise_name)

          {
            order: idx,
            exercise_id: db_exercise&.id&.to_s || generate_fallback_id(idx),
            exercise_name: db_exercise&.display_name || exercise_name,
            exercise_name_english: db_exercise&.english_name,
            target_muscle: ex["target_muscle"] || db_exercise&.muscle_group || "전신",
            sets: ex["sets"],
            reps: ex["reps"],
            rest_seconds: ex["rest_seconds"] || 60,
            instructions: ex["instructions"] || db_exercise&.form_tips,
            weight_description: ex["weight_guide"],
            rest_type: "time_based"
          }
        end

        {
          routine_id: "RT-#{@level}-#{Time.current.to_i}-#{SecureRandom.hex(4)}",
          generated_at: Time.current.iso8601,
          user_level: @level,
          tier: Constants.tier_for_level(@level),
          day_of_week: @day_of_week,
          training_type: data["training_focus"],
          exercises: exercises,
          estimated_duration_minutes: data["estimated_duration"] || 45,
          notes: [ data["warmup_notes"], data["cooldown_notes"], data["coach_message"] ].compact,
          creative: true,
          goal: @goal
        }
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse routine JSON: #{e.message}")
        fallback_routine
      end
    end
  end
end
