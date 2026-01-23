# frozen_string_literal: true

module Mutations
  class SaveRoutine < BaseMutation
    argument :level, String, required: true
    argument :week_number, Integer, required: true
    argument :day_number, Integer, required: true
    argument :workout_type, String, required: true
    argument :day_of_week, String, required: true
    argument :estimated_duration, Integer, required: true
    argument :exercises, [ Types::ExerciseInputType ], required: true

    field :workout_routine, Types::WorkoutRoutineType, null: true
    field :errors, [ String ], null: false

    VALID_LEVELS = %w[beginner intermediate advanced].freeze
    VALID_DAYS_OF_WEEK = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze
    WEEK_RANGE = (1..52).freeze
    DAY_RANGE = (1..7).freeze

    def resolve(level:, week_number:, day_number:, workout_type:, day_of_week:, estimated_duration:, exercises:)
      with_error_handling(workout_routine: nil) do
        user = authenticate!

        ActiveRecord::Base.transaction do
          workout_routine = user.workout_routines.create!(
            level: level,
            week_number: week_number,
            day_number: day_number,
            workout_type: workout_type,
            day_of_week: day_of_week,
            estimated_duration: estimated_duration,
            generated_at: Time.current
          )

          exercises.each do |exercise_input|
            workout_routine.routine_exercises.create!(exercise_input.to_h)
          end

          success_response(workout_routine: workout_routine.reload)
        end
      end
    end

    private

    def ready?(level:, week_number:, day_number:, day_of_week:, **args)
      unless VALID_LEVELS.include?(level)
        raise GraphQL::ExecutionError, "Invalid level. Must be: #{VALID_LEVELS.join(', ')}"
      end

      unless WEEK_RANGE.include?(week_number)
        raise GraphQL::ExecutionError, "Invalid week number. Must be between #{WEEK_RANGE.first} and #{WEEK_RANGE.last}"
      end

      unless DAY_RANGE.include?(day_number)
        raise GraphQL::ExecutionError, "Invalid day number. Must be between #{DAY_RANGE.first} and #{DAY_RANGE.last}"
      end

      unless VALID_DAYS_OF_WEEK.include?(day_of_week)
        raise GraphQL::ExecutionError, "Invalid day of week. Must be: #{VALID_DAYS_OF_WEEK.join(', ')}"
      end

      true
    end
  end
end
