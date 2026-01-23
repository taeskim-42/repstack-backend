# frozen_string_literal: true

module Types
  class ExerciseVerificationInputType < Types::BaseInputObject
    description "Input for exercise verification from CoreML pose estimation"

    argument :exercise_type, String, required: true,
             description: "Exercise type: bench, squat, or deadlift"
    argument :weight_kg, Float, required: true,
             description: "Weight lifted in kg"
    argument :reps, Int, required: false, default_value: 1,
             description: "Number of reps performed (default: 1 for 1RM test)"
    argument :pose_score, Float, required: false,
             description: "Form/pose score from CoreML (0-100)"
    argument :video_url, String, required: false,
             description: "URL to verification video"
    argument :form_issues, [String], required: false, default_value: [],
             description: "List of form issues detected by CoreML"
    argument :joint_angles, GraphQL::Types::JSON, required: false,
             description: "Joint angle data from pose estimation"
  end
end
