# frozen_string_literal: true

module AiTrainer
  module Shared
    # Builds fallback routines when LLM generation fails.
    # Requires including class to provide: find_exercise_by_name, generate_fallback_id
    module FallbackRoutineBuilder
      DEFAULT_EXERCISES = [
        { name: "푸시업", target: "가슴", reps: 10 },
        { name: "맨몸 스쿼트", target: "하체", reps: 10 },
        { name: "플랭크", target: "코어", work_seconds: 30, rest: 45 }
      ].freeze

      def build_default_exercise(name, order, target:, reps: nil, work_seconds: nil, rest: 60)
        db_exercise = find_exercise_by_name(name)
        is_time_based = work_seconds.present? || time_based_exercise?(name)

        {
          order: order,
          exercise_id: db_exercise&.id&.to_s || generate_fallback_id(order),
          exercise_name: db_exercise&.display_name || name,
          exercise_name_english: db_exercise&.english_name,
          target_muscle: db_exercise&.muscle_group || target,
          sets: 3,
          reps: is_time_based ? nil : (reps || 10),
          work_seconds: is_time_based ? (work_seconds || 30) : nil,
          rest_seconds: rest,
          rest_type: "time_based"
        }
      end

      def default_exercises_basic
        DEFAULT_EXERCISES.each_with_index.map do |ex, idx|
          build_default_exercise(
            ex[:name], idx + 1,
            target: ex[:target],
            reps: ex[:reps],
            work_seconds: ex[:work_seconds],
            rest: ex[:rest] || 60
          )
        end
      end
    end
  end
end
