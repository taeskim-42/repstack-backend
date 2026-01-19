# frozen_string_literal: true

module Types
  class FeedbackAnalysisType < Types::BaseObject
    description "AI analysis of workout feedback"

    field :insights, [String], null: false, description: "Feedback insights"
    field :adaptations, [String], null: false, description: "Suggested adaptations"
    field :next_workout_recommendations, [String], null: false, description: "Recommendations for next workout"
  end
end
