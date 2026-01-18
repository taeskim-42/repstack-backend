# frozen_string_literal: true

module Queries
  class MySessions < GraphQL::Schema::Resolver
    description "Get current user's workout sessions"

    type [Types::WorkoutSessionType], null: false
    argument :limit, Integer, required: false, default_value: 10

    def resolve(limit: 10)
      user = context[:current_user]
      return [] unless user

      user.workout_sessions
          .order(created_at: :desc)
          .limit([limit, 100].min) # Cap at 100 for performance
    end
  end
end