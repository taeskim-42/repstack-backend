# frozen_string_literal: true

module Types
  class WorkoutRecordItemType < Types::BaseObject
    description "Individual workout record item"

    field :date, String, null: false, description: "Record date (YYYY-MM-DD)"
    field :exercise_name, String, null: false, description: "Exercise name"
    field :weight, Float, null: true, description: "Weight in kg"
    field :reps, Integer, null: true, description: "Number of reps"
    field :sets, Integer, null: true, description: "Number of sets"
    field :volume, Float, null: true, description: "Total volume (weight x reps x sets)"
    field :recorded_at, GraphQL::Types::ISO8601DateTime, null: true, description: "Record timestamp"
  end
end
