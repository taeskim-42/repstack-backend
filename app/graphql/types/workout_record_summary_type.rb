# frozen_string_literal: true

module Types
  class WorkoutRecordSummaryType < Types::BaseObject
    description "Summary of a recorded workout"

    field :id, ID, null: false, description: "Record ID"
    field :date, String, null: false, description: "Workout date"
    field :total_duration, Integer, null: false, description: "Total duration in seconds"
    field :completion_status, Types::CompletionStatusEnum, null: false, description: "Completion status"
    field :calories_burned, Integer, null: true, description: "Calories burned during workout"
    field :average_heart_rate, Integer, null: true, description: "Average heart rate during workout"
    field :perceived_exertion, Integer, null: false, description: "Perceived exertion 1-10"
    field :routine_id, ID, null: true, description: "Associated routine ID"
    field :workout_session_id, ID, null: true, description: "Associated workout session ID"
  end
end
