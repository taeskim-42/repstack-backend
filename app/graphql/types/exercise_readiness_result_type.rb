# frozen_string_literal: true

module Types
  class ExerciseReadinessResultType < Types::BaseObject
    description "Individual exercise readiness result"

    field :exercise_type, String, null: false
    field :status, String, null: false, description: "passed, failed, or no_data"
    field :estimated_1rm, Float, null: true
    field :required, Float, null: true
    field :surplus, Float, null: true, description: "Amount above requirement (if passed)"
    field :gap, Float, null: true, description: "Amount below requirement (if failed)"
    field :message, String, null: true
  end
end
