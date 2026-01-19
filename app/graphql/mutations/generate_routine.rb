# frozen_string_literal: true

module Mutations
  class GenerateRoutine < BaseMutation
    description "Generate a workout routine using AI"

    argument :level, String, required: true, description: "Training level (beginner, intermediate, advanced)"
    argument :week, Integer, required: true, description: "Week number (1-52)"
    argument :day, Integer, required: true, description: "Day number (1-7)"
    argument :body_info, Types::BodyInfoInputType, required: false, description: "User body information"

    field :routine, Types::RoutineType, null: true
    field :errors, [String], null: false
    field :is_mock, Boolean, null: false, description: "Whether the routine is mock data (API not configured)"

    def resolve(level:, week:, day:, body_info: nil)
      service = ClaudeApiService.new
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      body_info_hash = body_info&.to_h || {}
      result = service.generate_routine(
        level: level,
        week: week,
        day: day,
        body_info: body_info_hash
      )

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      if result[:success]
        MetricsService.record_routine_generation(
          success: true,
          level: level,
          mock: result[:mock] || false,
          duration_seconds: duration
        )

        routine = transform_routine_data(result[:data])
        {
          routine: routine,
          errors: [],
          is_mock: result[:mock] || false
        }
      else
        MetricsService.record_routine_generation(
          success: false,
          level: level,
          mock: false,
          duration_seconds: duration
        )

        {
          routine: nil,
          errors: [result[:error] || "Failed to generate routine"],
          is_mock: false
        }
      end
    end

    private

    def transform_routine_data(data)
      return nil unless data

      {
        workout_type: data["workoutType"],
        day_of_week: data["dayOfWeek"],
        estimated_duration: data["estimatedDuration"],
        exercises: transform_exercises(data["exercises"])
      }
    end

    def transform_exercises(exercises)
      return [] unless exercises.is_a?(Array)

      exercises.map do |ex|
        {
          exercise_name: ex["exerciseName"],
          target_muscle: ex["targetMuscle"],
          sets: ex["sets"],
          reps: ex["reps"],
          weight: ex["weight"],
          weight_description: ex["weightDescription"],
          bpm: ex["bpm"],
          set_duration_seconds: ex["setDurationSeconds"],
          rest_duration_seconds: ex["restDurationSeconds"],
          range_of_motion: ex["rangeOfMotion"],
          how_to: ex["howTo"],
          purpose: ex["purpose"]
        }
      end
    end
  end
end