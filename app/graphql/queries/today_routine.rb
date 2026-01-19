# frozen_string_literal: true

module Queries
  class TodayRoutine < GraphQL::Schema::Resolver
    description "Get today's workout routine for the current user"

    type Types::WorkoutRoutineType, null: true

    # Map of day name variants for flexible matching
    DAY_NAME_VARIANTS = {
      "Monday" => %w[Monday MONDAY monday Mon MON],
      "Tuesday" => %w[Tuesday TUESDAY tuesday Tue TUE],
      "Wednesday" => %w[Wednesday WEDNESDAY wednesday Wed WED],
      "Thursday" => %w[Thursday THURSDAY thursday Thu THU],
      "Friday" => %w[Friday FRIDAY friday Fri FRI],
      "Saturday" => %w[Saturday SATURDAY saturday Sat SAT],
      "Sunday" => %w[Sunday SUNDAY sunday Sun SUN]
    }.freeze

    def resolve
      user = context[:current_user]
      return nil unless user

      profile = user.user_profile
      return nil unless profile

      # Get current day name in standard format
      current_day = Date.current.strftime("%A")
      day_variants = DAY_NAME_VARIANTS[current_day] || [current_day]

      # Find routine matching user's progress and today's day
      # Use includes to prevent N+1 when accessing routine_exercises
      user.workout_routines
          .includes(:routine_exercises)
          .where(
            level: profile.current_level,
            week_number: profile.week_number,
            day_number: profile.day_number,
            is_completed: false
          )
          .where(day_of_week: day_variants)
          .order(created_at: :desc)
          .first
    end
  end
end