# frozen_string_literal: true

module Types
  class UserLevelAssessmentType < Types::BaseObject
    description "User's level assessment data"

    field :user_id, ID, null: false, description: "User ID"
    field :level, Types::TrainingLevelEnum, null: false, description: "Training level"
    field :assessment_data, GraphQL::Types::JSON, null: true, description: "Original assessment input"
    field :fitness_factors, Types::FitnessFactorsType, null: true, description: "Fitness factors"
    field :max_lifts, GraphQL::Types::JSON, null: true, description: "Maximum lifts by exercise"
    field :assessed_at, String, null: false, description: "Assessment date ISO 8601"
    field :valid_until, String, null: false, description: "Assessment expiry date ISO 8601"
  end
end
