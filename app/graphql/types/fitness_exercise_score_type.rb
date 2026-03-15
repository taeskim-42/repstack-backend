# frozen_string_literal: true

module Types
  class FitnessExerciseScoreType < Types::BaseObject
    description "Score details for a single fitness test exercise"

    field :count, Integer, null: false,
      description: "Number of reps completed"
    field :tier, String, null: false,
      description: "Performance tier (poor/fair/good/excellent/elite)"
    field :tier_name, String, null: false,
      description: "Performance tier in user's locale"
    field :tier_korean, String, null: false,
      description: "Performance tier in Korean",
      deprecation_reason: "Use tierName instead"
    field :points, Integer, null: false,
      description: "Points earned (1-5)"

    def tier_name
      locale = context[:locale] || "ko"
      tier_val = object.is_a?(Hash) ? (object[:tier] || object["tier"]) : nil
      Localizable.translate(:exercise_tiers, tier_val, locale)
    end
  end
end
