# frozen_string_literal: true

module Types
  class FitnessVideoInputType < Types::BaseInputObject
    description "Input for a single fitness test video"

    argument :exercise_type, String, required: true,
      description: "Type of exercise (e.g., 'pushup', 'squat', 'pullup', 'bench_press', 'deadlift')"
    argument :video_key, String, required: true,
      description: "S3 key for the uploaded video"
  end
end
