# frozen_string_literal: true

module Types
  class FitnessTestSubmissionType < Types::BaseObject
    description "Video-based fitness test submission with analysis results"

    field :id, ID, null: false
    field :job_id, String, null: false, description: "Unique job identifier for tracking"
    field :status, FitnessTestSubmissionStatusEnum, null: false, description: "Current processing status"

    # Videos (dynamic array)
    field :videos, [FitnessVideoType], null: false, description: "Submitted exercise videos"

    # Analyses (dynamic hash)
    field :analyses, [VideoAnalysisDetailsType], null: false, description: "Analysis results for each exercise"

    # Final evaluation
    field :fitness_score, Integer, null: true, description: "Overall fitness score (0-100)"
    field :assigned_level, Integer, null: true, description: "Assigned numeric level (1-7)"
    field :assigned_tier, String, null: true, description: "Assigned tier (beginner/intermediate/advanced)"
    field :message, String, null: true, description: "Motivational message for the user"
    field :recommendations, [String], null: true, description: "Training recommendations"

    # Error info
    field :error_message, String, null: true, description: "Error message if analysis failed"

    # Timestamps
    field :started_at, GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def videos
      object.videos.map do |v|
        {
          exercise_type: v["exercise_type"],
          video_key: v["video_key"]
        }
      end
    end

    def analyses
      object.analyses.map do |exercise_type, analysis|
        {
          exercise_type: exercise_type,
          rep_count: analysis["rep_count"] || analysis[:rep_count] || 0,
          form_score: analysis["form_score"] || analysis[:form_score] || 0,
          issues: analysis["issues"] || analysis[:issues] || [],
          feedback: analysis["feedback"] || analysis[:feedback]
        }
      end
    end

    def message
      object.evaluation_result&.dig("message")
    end

    def recommendations
      object.evaluation_result&.dig("recommendations")
    end
  end
end
