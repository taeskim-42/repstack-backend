# frozen_string_literal: true

module Types
  class FeedbackSummaryType < Types::BaseObject
    description "Summary of submitted feedback"

    field :id, ID, null: false, description: "Feedback ID"
    field :rating, Integer, null: false, description: "Rating 1-5"
    field :feedback_type, Types::FeedbackTypeEnum, null: false, description: "Feedback type"
  end
end
