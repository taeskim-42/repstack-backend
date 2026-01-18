# frozen_string_literal: true

module Types
  class ExerciseInputType < Types::BaseInputObject
    description "Input type for routine exercises"

    argument :exercise_name, String, required: true, description: "Name of the exercise"
    argument :target_muscle, String, required: true, description: "Target muscle group"
    argument :order_index, Integer, required: true, description: "Order in the routine"
    argument :sets, Integer, required: true, description: "Number of sets"
    argument :reps, Integer, required: true, description: "Number of repetitions"
    argument :weight, Float, required: false, description: "Weight to use"
    argument :weight_description, String, required: false, description: "Weight description"
    argument :bpm, Integer, required: false, description: "Beats per minute for cardio"
    argument :rest_duration_seconds, Integer, required: true, description: "Rest duration between sets"
    argument :range_of_motion, String, required: true, description: "Range of motion description"
    argument :how_to, String, required: true, description: "Exercise instructions"
    argument :purpose, String, required: true, description: "Purpose of the exercise"
  end
end