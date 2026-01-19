# frozen_string_literal: true

module Types
  class ConditionStatusType < Types::BaseObject
    description "User's condition status affecting the workout"

    field :score, Float, null: false, description: "Condition score (1.0-5.0)"
    field :status, String, null: false, description: "Status in Korean (최상/양호/보통/나쁨)"
    field :volume_modifier, Float, null: false, description: "Volume adjustment multiplier"
    field :intensity_modifier, Float, null: false, description: "Intensity adjustment multiplier"
  end
end
