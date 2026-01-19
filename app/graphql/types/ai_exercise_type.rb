# frozen_string_literal: true

module Types
  class AiExerciseType < Types::BaseObject
    description "Exercise in an AI-generated routine"

    field :order, Integer, null: false
    field :exercise_id, String, null: false
    field :exercise_name, String, null: false
    field :exercise_name_english, String, null: true
    field :target_muscle, String, null: false
    field :target_muscle_korean, String, null: true
    field :equipment, String, null: true

    # Training parameters
    field :sets, GraphQL::Types::JSON, null: true, description: "Number of sets or 'until_complete'"
    field :reps, GraphQL::Types::JSON, null: true, description: "Reps per set or 'max_per_set'"
    field :target_total_reps, Integer, null: true, description: "Target total reps for endurance training"
    field :bpm, Integer, null: true, description: "BPM for tempo training"
    field :rest_seconds, Integer, null: true
    field :rest_type, String, null: true, description: "time_based or heart_rate_based"
    field :heart_rate_threshold, Float, null: true, description: "HR threshold for HR-based rest"
    field :range_of_motion, String, null: true, description: "full/medium/short"

    # Weight info
    field :target_weight_kg, Float, null: true
    field :weight_description, String, null: true

    # Tabata specific
    field :work_seconds, Integer, null: true
    field :rounds, Integer, null: true

    # Instructions
    field :instructions, String, null: true
  end
end
