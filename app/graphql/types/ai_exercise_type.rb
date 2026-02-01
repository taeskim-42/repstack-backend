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
    field :rpe, Integer, null: true, description: "Rate of Perceived Exertion (1-10)"
    field :tempo, String, null: true, description: "Exercise tempo (e.g., 3-1-2)"
    field :rom, String, null: true, description: "Range of motion (full/partial/stretch)"
    field :rest_seconds, Integer, null: true
    field :rest_type, String, null: true, description: "time_based or heart_rate_based"
    field :heart_rate_threshold, Float, null: true, description: "HR threshold for HR-based rest"
    field :range_of_motion, String, null: true, description: "full/medium/short (legacy)"

    # Weight info
    field :target_weight_kg, Float, null: true
    field :weight_description, String, null: true
    field :weight_guide, String, null: true, description: "Weight selection guidance"

    # Tabata specific
    field :work_seconds, Integer, null: true
    field :rounds, Integer, null: true

    # Instructions
    field :instructions, String, null: true
    field :source_program, String, null: true, description: "Reference program (e.g., 심현도, 김성환)"

    # Knowledge enrichment (from YouTube RAG)
    field :expert_tips, [String], null: true, description: "Expert tips from fitness knowledge base"
    field :form_cues, [String], null: true, description: "Form/posture cues for proper execution"
    field :video_references, [Types::VideoReferenceType], null: true, description: "Related YouTube video references"
  end
end
