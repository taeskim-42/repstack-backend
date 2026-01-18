# frozen_string_literal: true

module Queries
  class TodayRoutine < GraphQL::Schema::Resolver
    description "Get today's workout routine for the current user"

    type Types::WorkoutRoutineType, null: true

    def resolve
      user = context[:current_user]
      return nil unless user

      profile = user.user_profile
      return nil unless profile

      # Get current day of week and try to find a matching routine
      current_day_of_week = Date.current.strftime('%A')
      
      # Find routine based on user's current progress
      user.workout_routines
          .where(
            level: profile.current_level,
            week_number: profile.week_number,
            day_number: profile.day_number,
            day_of_week: current_day_of_week
          )
          .order(:created_at)
          .last
    end
  end
end