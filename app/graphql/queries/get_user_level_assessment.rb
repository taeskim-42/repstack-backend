# frozen_string_literal: true

module Queries
  class GetUserLevelAssessment < Queries::BaseQuery
    description "Get user's current level assessment"

    type Types::UserLevelAssessmentType, null: true

    def resolve
      authenticate_user!

      profile = current_user.user_profile
      return nil unless profile&.level_assessed_at

      {
        user_id: current_user.id,
        level: profile.current_level&.upcase || "BEGINNER",
        assessment_data: nil,
        fitness_factors: profile.fitness_factors,
        max_lifts: profile.max_lifts || {},
        assessed_at: profile.level_assessed_at.iso8601,
        valid_until: (profile.level_assessed_at + 90.days).iso8601
      }
    end
  end
end
