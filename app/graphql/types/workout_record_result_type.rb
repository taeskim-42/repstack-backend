# frozen_string_literal: true

module Types
  class WorkoutRecordResultType < Types::BaseObject
    description "Result of recording a workout"

    field :success, Boolean, null: false, description: "Whether recording was successful"
    field :workout_record, Types::WorkoutRecordSummaryType, null: true, description: "Recorded workout summary"
    field :error, String, null: true, description: "Error message if failed"
  end
end
