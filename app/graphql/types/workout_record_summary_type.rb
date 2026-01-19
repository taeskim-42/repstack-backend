# frozen_string_literal: true

module Types
  class WorkoutRecordSummaryType < Types::BaseObject
    description "Summary of a recorded workout"

    field :id, ID, null: false, description: "Record ID"
    field :date, String, null: false, description: "Workout date"
    field :total_duration, Integer, null: false, description: "Total duration in seconds"
    field :completion_status, Types::CompletionStatusEnum, null: false, description: "Completion status"
  end
end
