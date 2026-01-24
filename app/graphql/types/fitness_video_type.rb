# frozen_string_literal: true

module Types
  class FitnessVideoType < Types::BaseObject
    description "A fitness test video entry"

    field :exercise_type, String, null: false, description: "Type of exercise"
    field :video_key, String, null: false, description: "S3 key for the video"
  end
end
