# frozen_string_literal: true

module Types
  class WorkoutRecordInputType < Types::BaseInputObject
    description "Input for recording a completed workout"

    argument :routine_id, ID, required: true,
      description: "ID of the routine that was performed"
    argument :date, String, required: false,
      description: "ISO 8601 date string"
    argument :exercises, [Types::ExerciseRecordInputType], required: true,
      description: "Array of exercise records"
    argument :total_duration, Integer, required: true,
      description: "Total workout duration in seconds"
    argument :calories_burned, Integer, required: false,
      description: "Estimated calories burned"
    argument :average_heart_rate, Integer, required: false,
      description: "Average heart rate during workout"
    argument :perceived_exertion, Integer, required: true,
      description: "Overall RPE 1-10"
    argument :notes, String, required: false,
      description: "Workout notes"
    argument :completion_status, Types::CompletionStatusEnum, required: true,
      description: "Workout completion status"
  end
end
