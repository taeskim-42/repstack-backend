# frozen_string_literal: true

module Types
  class ConditionResultType < Types::BaseObject
    description "Result of condition check"

    field :success, Boolean, null: false, description: "Whether the check was successful"
    field :adaptations, [String], null: true, description: "Recommended adaptations"
    field :intensity_modifier, Float, null: true, description: "Intensity modifier 0.5-1.5"
    field :duration_modifier, Float, null: true, description: "Duration modifier 0.7-1.3"
    field :exercise_modifications, [String], null: true, description: "Exercise modifications"
    field :rest_recommendations, [String], null: true, description: "Rest recommendations"
    field :error, String, null: true, description: "Error message if failed"
  end
end
