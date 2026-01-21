# frozen_string_literal: true

module Types
  class OfflineRecordInputType < Types::BaseInputObject
    description "Input for a single offline workout record"

    argument :client_id, String, required: true, description: "Client-generated UUID for deduplication"
    argument :exercise_name, String, required: true, description: "Exercise name"
    argument :weight, Float, required: false, description: "Weight in kg"
    argument :reps, Integer, required: true, description: "Number of reps"
    argument :sets, Integer, required: false, default_value: 1, description: "Number of sets"
    argument :recorded_at, GraphQL::Types::ISO8601DateTime, required: true, description: "When the exercise was recorded offline"
  end
end
