# frozen_string_literal: true

module Types
  class VoiceFeedbackResultType < Types::BaseObject
    description "Result of voice feedback analysis"

    field :id, ID, null: true, description: "Feedback record ID (if saved)"
    field :rating, Integer, null: false, description: "Inferred rating 1-5"
    field :feedback_type, String, null: false, description: "Inferred feedback type"
    field :summary, String, null: true, description: "AI-generated summary"
    field :would_recommend, Boolean, null: false, description: "Inferred recommendation"
  end
end
