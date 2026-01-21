# frozen_string_literal: true

module Types
  class RoutineExerciseInputType < Types::BaseInputObject
    description "Input for a routine exercise"

    argument :exercise_name, String, required: true
    argument :exercise_id, String, required: false, description: "Exercise ID from catalog"
    argument :target_muscle, String, required: false
    argument :sets, Integer, required: false, default_value: 3
    argument :reps, Integer, required: false, default_value: 10
    argument :weight, Float, required: false
    argument :weight_description, String, required: false
    argument :bpm, Integer, required: false
    argument :rest_duration_seconds, Integer, required: false, default_value: 60
    argument :range_of_motion, String, required: false
    argument :how_to, String, required: false
    argument :purpose, String, required: false
    argument :order_index, Integer, required: true
  end
end
