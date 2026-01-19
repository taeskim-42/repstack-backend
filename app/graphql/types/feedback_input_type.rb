# frozen_string_literal: true

module Types
  class FeedbackInputType < Types::BaseInputObject
    description "Input for submitting workout feedback"

    argument :workout_record_id, ID, required: true,
      description: "ID of the workout record"
    argument :routine_id, ID, required: true,
      description: "ID of the routine"
    argument :feedback_type, Types::FeedbackTypeEnum, required: true,
      description: "Type of feedback"
    argument :rating, Integer, required: true,
      description: "Rating 1-5 scale"
    argument :feedback, String, required: true,
      description: "Feedback text"
    argument :suggestions, [String], required: false,
      description: "Suggestions for improvement"
    argument :would_recommend, Boolean, required: true,
      description: "Would recommend this workout"
  end
end
