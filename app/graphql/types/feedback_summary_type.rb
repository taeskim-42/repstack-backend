# frozen_string_literal: true

module Types
  class FeedbackSummaryType < Types::BaseObject
    description "Summary of submitted feedback"

    field :id, ID, null: false, description: "Feedback ID"
    field :rating, Integer, null: false, description: "Rating 1-5"
    field :feedback_type, Types::FeedbackTypeEnum, null: false, description: "Feedback type"
    field :feedback, String, null: false, description: "Feedback text"
    field :suggestions, [String], null: true, description: "Improvement suggestions"
    field :would_recommend, Boolean, null: false, description: "Would recommend to others"
    field :workout_record_id, ID, null: true, description: "Associated workout record ID"
    field :routine_id, ID, null: true, description: "Associated routine ID"
  end
end
