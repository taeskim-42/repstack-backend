# frozen_string_literal: true

module Types
  class ConditionAnalysisType < Types::BaseObject
    description "Condition analysis result from chat"

    field :score, Float, null: true, description: "Condition score (0-100)"
    field :status, String, null: true, description: "Condition status (excellent, good, fair, poor)"
    field :adaptations, [String], null: true, description: "Suggested workout adaptations"
    field :recommendations, [String], null: true, description: "General recommendations"
  end
end
