# frozen_string_literal: true

module Queries
  class MySessions < GraphQL::Schema::Resolver
    description "Get current user's workout sessions"

    type [Types::WorkoutSessionType], null: false

    argument :limit, Integer, required: false, default_value: 10
    argument :include_sets, Boolean, required: false, default_value: true

    MAX_LIMIT = 100

    def resolve(limit: 10, include_sets: true)
      user = context[:current_user]
      return [] unless user

      scope = user.workout_sessions
      scope = scope.includes(:workout_sets) if include_sets
      scope.order(created_at: :desc)
           .limit([limit, MAX_LIMIT].min)
    end
  end
end