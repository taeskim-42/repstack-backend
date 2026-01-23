# frozen_string_literal: true

module Types
  class AiRoutineType < Types::BaseObject
    description "AI-generated workout routine with infinite variations"

    field :routine_id, String, null: false, description: "Unique routine identifier"
    field :generated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :user_level, Integer, null: false, description: "User's numeric level (1-8)"
    field :tier, String, null: false, description: "Level tier (beginner/intermediate/advanced)"
    field :day_of_week, String, null: false
    field :day_korean, String, null: false
    field :fitness_factor, String, null: false, description: "Today's fitness factor"
    field :fitness_factor_korean, String, null: false
    field :training_method, String, null: true
    field :training_method_info, Types::TrainingMethodInfoType, null: true
    field :condition, Types::ConditionStatusType, null: false
    field :estimated_duration_minutes, Integer, null: false
    field :exercises, [ Types::AiExerciseType ], null: false
    field :notes, [ String ], null: true
  end
end
