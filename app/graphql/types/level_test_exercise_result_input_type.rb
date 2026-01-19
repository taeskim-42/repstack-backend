# frozen_string_literal: true

module Types
  class LevelTestExerciseResultInputType < Types::BaseInputObject
    description "Input for submitting exercise results in a level test"

    argument :exercise_type, String, required: true,
      description: "Exercise type (bench, squat, deadlift)"
    argument :weight_kg, Float, required: true,
      description: "Weight lifted in kg"
    argument :reps, Integer, required: true,
      description: "Number of reps completed"
  end
end
