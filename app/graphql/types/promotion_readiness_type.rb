# frozen_string_literal: true

module Types
  class PromotionReadinessType < Types::BaseObject
    description "Result of promotion readiness check based on estimated 1RM"

    field :eligible, Boolean, null: false,
          description: "Whether user is ready for promotion"
    field :current_level, Int, null: false
    field :target_level, Int, null: false
    field :estimated_1rms, Types::OneRmValuesType, null: true,
          description: "Estimated 1RM values from workout history"
    field :required_1rms, Types::OneRmValuesType, null: true,
          description: "Required 1RM values for promotion"
    field :exercise_results, [Types::ExerciseReadinessResultType], null: false,
          description: "Detailed results for each exercise"
    field :ai_feedback, String, null: true,
          description: "AI-generated feedback on promotion readiness"
    field :recommendation, String, null: false,
          description: "Recommendation: ready_for_promotion, continue_training, login_required, profile_required"
  end
end
