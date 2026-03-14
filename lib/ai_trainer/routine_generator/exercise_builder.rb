# frozen_string_literal: true

require_relative "../shared/exercise_finder"

module AiTrainer
  class RoutineGenerator
    # Builds exercise hashes from WorkoutPrograms data with condition adjustment.
    # Depends on the host class providing: @adjustment, @level, @day_of_week
    module ExerciseBuilder
      include Shared::ExerciseFinder

      # Build full exercise list with condition-adjusted sets/reps
      def build_exercises(workout)
        workout[:exercises].map.with_index(1) do |ex, order|
          adjusted = apply_condition_adjustment(ex)
          exercise_name = ex[:name]
          db_exercise = find_exercise_by_name(exercise_name)

          {
            order: order,
            exercise_id: db_exercise&.id&.to_s || generate_fallback_id(order),
            exercise_name: db_exercise&.display_name || exercise_name,
            exercise_name_english: db_exercise&.english_name,
            target_muscle: ex[:target] || db_exercise&.muscle_group,
            sets: adjusted[:sets],
            reps: adjusted[:reps],
            target_total_reps: adjusted[:target_total_reps],
            weight_description: ex[:weight],
            bpm: ex[:bpm],
            range_of_motion: format_rom(ex[:rom]),
            work_seconds: ex[:work_seconds],
            how_to: ex[:how_to],
            rest_seconds: calculate_rest_seconds(workout[:training_type]),
            rest_type: ex[:work_seconds] ? "tabata" : "time_based",
            instructions: ex[:how_to] || db_exercise&.form_tips || default_instruction(workout[:training_type])
          }
        end
      end

      private

      # Adjust sets/reps based on condition modifiers
      def apply_condition_adjustment(exercise)
        sets = exercise[:sets]
        reps = exercise[:reps]
        target_total_reps = nil

        volume_mod = @adjustment[:volume_modifier]
        intensity_mod = @adjustment[:intensity_modifier]

        # "채우기" style: sets = nil, reps = total target
        if sets.nil? && reps && reps >= 100
          target_total_reps = (reps * volume_mod).round
          sets = nil
          reps = nil
        elsif sets && reps
          adjusted_sets = (sets * volume_mod).round
          adjusted_reps = (reps * intensity_mod).round
          sets = [ [ adjusted_sets, 1 ].max, sets + 2 ].min
          reps = [ [ adjusted_reps, 1 ].max, reps + 5 ].min
        end

        { sets: sets, reps: reps, target_total_reps: target_total_reps }
      end

      def format_rom(rom)
        case rom
        when :full then "full"
        when :medium then "medium"
        when :short then "short"
        else "full"
        end
      end

      def calculate_rest_seconds(training_type)
        case training_type
        when :strength, :strength_power then 90
        when :muscular_endurance then 60
        when :sustainability then 60
        when :cardiovascular then 10
        when :form_practice then 120
        else 60
        end
      end

      def default_instruction(training_type)
        case training_type
        when :strength then "BPM에 맞춰 정확한 자세로 수행하세요."
        when :muscular_endurance then "목표 횟수를 채울 때까지 최대 횟수로 세트를 수행하세요."
        when :sustainability then "10개씩 몇 세트까지 지속 가능한지 확인하세요."
        when :cardiovascular then "20초간 최대한 빠르게 수행 후 10초 휴식하세요."
        when :strength_power then "점진적으로 무게를 증량한 후, 실패 시점부터 드랍세트로 진행하세요."
        else "바른 자세로 천천히 수행하세요."
        end
      end
    end
  end
end
