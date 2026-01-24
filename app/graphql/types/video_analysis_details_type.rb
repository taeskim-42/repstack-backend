# frozen_string_literal: true

module Types
  class VideoAnalysisDetailsType < Types::BaseObject
    description "Detailed results from video analysis of an exercise"

    field :exercise_type, String, null: false, description: "Type of exercise analyzed"
    field :rep_count, Integer, null: false, description: "Number of repetitions detected"
    field :form_score, Integer, null: false, description: "Form quality score (0-100)"
    field :issues, [String], null: false, description: "List of detected form issues"
    field :feedback, String, null: true, description: "Feedback for improvement"
  end
end
