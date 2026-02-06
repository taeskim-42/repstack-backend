# frozen_string_literal: true

module Queries
  class MySessions < BaseQuery
    description "Get current user's workout sessions"

    type [ Types::WorkoutSessionType ], null: false

    argument :limit, Integer, required: false, default_value: 10
    argument :include_sets, Boolean, required: false, default_value: true
    argument :date, String, required: false, description: "Filter by date (ISO 8601, e.g. '2026-02-06')"

    MAX_LIMIT = 100

    def resolve(limit: 10, include_sets: true, date: nil)
      authenticate_user!

      scope = current_user.workout_sessions
      scope = scope.includes(:workout_sets) if include_sets
      if date.present?
        parsed_date = begin; Date.iso8601(date); rescue ArgumentError; Date.parse(date) rescue nil; end
        scope = scope.for_date(parsed_date) if parsed_date
      end
      scope.order(created_at: :desc)
           .limit([ limit, MAX_LIMIT ].min)
    end
  end
end
