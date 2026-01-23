# frozen_string_literal: true

module Types
  class WorkoutSetInputType < Types::BaseInputObject
    description "Input type for creating workout sets"

    argument :exercise_name, String, required: true, description: "Name of the exercise"
    argument :weight, Float, required: false, description: "Weight used"
    argument :weight_unit, String, required: false, description: "Unit of weight (kg/lbs)", default_value: "kg"
    argument :reps, Integer, required: false, description: "Number of repetitions"
    argument :duration_seconds, Integer, required: false, description: "Duration in seconds for time-based exercises"
    argument :notes, String, required: false, description: "Additional notes"
  end
end
