# frozen_string_literal: true

module Types
  class ExerciseVerificationResultType < Types::BaseObject
    description "Individual exercise verification result"

    field :exercise_type, String, null: false
    field :weight_kg, Float, null: false
    field :passed, Boolean, null: false
    field :pose_score, Float, null: true
    field :video_url, String, null: true
    field :form_issues, [String], null: true
    field :verified_at, String, null: true
  end
end
