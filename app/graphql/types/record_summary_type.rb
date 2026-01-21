# frozen_string_literal: true

module Types
  class RecordSummaryType < Types::BaseObject
    description "Summary of workout records"

    field :max_weight, Float, null: true, description: "Maximum weight lifted"
    field :max_reps, Integer, null: true, description: "Maximum reps in a single set"
    field :avg_weight, Float, null: true, description: "Average weight"
    field :total_volume, Float, null: true, description: "Total volume (sum of weight x reps)"
    field :total_sets, Integer, null: true, description: "Total number of sets"
    field :total_workouts, Integer, null: true, description: "Total number of workout sessions"
  end
end
