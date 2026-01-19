# frozen_string_literal: true

module Types
  class FeedbackResultType < Types::BaseObject
    description "Result of submitting feedback"

    field :success, Boolean, null: false, description: "Whether submission was successful"
    field :feedback, Types::FeedbackSummaryType, null: true, description: "Feedback summary"
    field :analysis, Types::FeedbackAnalysisType, null: true, description: "AI analysis of feedback"
    field :error, String, null: true, description: "Error message if failed"
  end
end
