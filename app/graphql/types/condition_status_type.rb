# frozen_string_literal: true

module Types
  class ConditionStatusType < Types::BaseObject
    description "User's condition status affecting the workout"

    field :score, Float, null: false, description: "Condition score (1.0-5.0)"
    field :status, String, null: false, description: "Status in Korean (최상/양호/보통/나쁨)"
    field :status_name, String, null: false, description: "Condition status name in user's locale"
    field :volume_modifier, Float, null: false, description: "Volume adjustment multiplier"
    field :intensity_modifier, Float, null: false, description: "Intensity adjustment multiplier"

    def status_name
      locale = context[:locale] || "ko"
      score = object.is_a?(Hash) ? (object[:score] || object["score"] || 3.0) : 3.0
      condition_key = case score.to_f
      when 4.0..5.0 then "excellent"
      when 3.0...4.0 then "good"
      when 2.0...3.0 then "moderate"
      else "poor"
      end
      Localizable.translate(:conditions, condition_key, locale)
    end
  end
end
