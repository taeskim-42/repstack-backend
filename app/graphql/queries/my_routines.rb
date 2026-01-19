# frozen_string_literal: true

module Queries
  class MyRoutines < GraphQL::Schema::Resolver
    description "Get current user's workout routines"

    type [Types::WorkoutRoutineType], null: false

    argument :limit, Integer, required: false, default_value: 10
    argument :completed_only, Boolean, required: false, default_value: false

    MAX_LIMIT = 100

    def resolve(limit: 10, completed_only: false)
      user = context[:current_user]
      return [] unless user

      scope = user.workout_routines.includes(:routine_exercises)
      scope = scope.completed if completed_only
      scope.order(created_at: :desc)
           .limit([limit, MAX_LIMIT].min)
    end
  end
end