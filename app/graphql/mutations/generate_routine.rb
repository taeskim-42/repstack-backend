# frozen_string_literal: true

module Mutations
  class GenerateRoutine < BaseMutation
    description "Generate a workout routine using AI"

    argument :level, String, required: true, description: "Training level (beginner, intermediate, advanced)"
    argument :week, Integer, required: true, description: "Week number (1-4)"
    argument :day, Integer, required: true, description: "Day number (1-5)"
    argument :body_info, Types::BodyInfoInputType, required: false, description: "User body information"

    field :routine, Types::RoutineType, null: true
    field :errors, [String], null: false

    def resolve(level:, week:, day:, body_info: nil)
      service = ClaudeApiService.new

      body_info_hash = body_info&.to_h || {}
      result = service.generate_routine(
        level: level,
        week: week,
        day: day,
        body_info: body_info_hash
      )

      if result && result["exercises"]
        routine = {
          workout_type: result["workoutType"],
          day_of_week: result["dayOfWeek"],
          estimated_duration: result["estimatedDuration"],
          exercises: result["exercises"].map do |ex|
            {
              exercise_name: ex["exerciseName"],
              target_muscle: ex["targetMuscle"],
              sets: ex["sets"],
              reps: ex["reps"],
              weight: ex["weight"],
              weight_description: ex["weightDescription"],
              bpm: ex["bpm"],
              rest_duration_seconds: ex["restDurationSeconds"],
              range_of_motion: ex["rangeOfMotion"],
              how_to: ex["howTo"],
              purpose: ex["purpose"]
            }
          end
        }

        { routine: routine, errors: [] }
      else
        { routine: nil, errors: ["Failed to generate routine"] }
      end
    end
  end
end
