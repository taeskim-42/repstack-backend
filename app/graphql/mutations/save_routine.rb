# frozen_string_literal: true

module Mutations
  class SaveRoutine < BaseMutation
    argument :level, String, required: true
    argument :week_number, Integer, required: true
    argument :day_number, Integer, required: true
    argument :workout_type, String, required: true
    argument :day_of_week, String, required: true
    argument :estimated_duration, Integer, required: true
    argument :exercises, [Types::ExerciseInputType], required: true

    field :workout_routine, Types::WorkoutRoutineType, null: true
    field :errors, [String], null: false

    def resolve(level:, week_number:, day_number:, workout_type:, day_of_week:, estimated_duration:, exercises:)
      user = context[:current_user]
      
      unless user
        return {
          workout_routine: nil,
          errors: ['Authentication required']
        }
      end

      # Create workout routine
      workout_routine = user.workout_routines.build(
        level: level,
        week_number: week_number,
        day_number: day_number,
        workout_type: workout_type,
        day_of_week: day_of_week,
        estimated_duration: estimated_duration,
        generated_at: Time.current
      )

      if workout_routine.save
        # Create routine exercises
        exercises.each do |exercise_input|
          exercise_attrs = exercise_input.to_h
          workout_routine.routine_exercises.create!(exercise_attrs)
        end

        {
          workout_routine: workout_routine.reload,
          errors: []
        }
      else
        {
          workout_routine: nil,
          errors: workout_routine.errors.full_messages
        }
      end
    rescue StandardError => e
      {
        workout_routine: nil,
        errors: [e.message]
      }
    end

    private

    def ready?(level:, week_number:, day_number:, day_of_week:, **args)
      unless %w[beginner intermediate advanced].include?(level)
        raise GraphQL::ExecutionError, 'Invalid level. Must be beginner, intermediate, or advanced'
      end

      unless (1..52).include?(week_number)
        raise GraphQL::ExecutionError, 'Invalid week number. Must be between 1 and 52'
      end

      unless (1..7).include?(day_number)
        raise GraphQL::ExecutionError, 'Invalid day number. Must be between 1 and 7'
      end

      unless %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].include?(day_of_week)
        raise GraphQL::ExecutionError, 'Invalid day of week'
      end

      true
    end
  end
end