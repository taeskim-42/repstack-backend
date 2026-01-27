# frozen_string_literal: true

module Mutations
  class AnalyzeVideo < BaseMutation
    description "Analyze a single video for exercise counting (for testing/demo)"

    argument :video_url, String, required: true,
             description: "URL to the video (YouTube URL or presigned URL)"
    argument :exercise_type, String, required: false,
             description: "Exercise type for specific criteria (e.g., pushup, squat)"

    field :success, Boolean, null: false
    field :rep_count, Integer, null: true
    field :form_score, Integer, null: true
    field :exercise_detected, String, null: true
    field :issues, [String], null: true
    field :feedback, String, null: true
    field :error, String, null: true

    def resolve(video_url:, exercise_type: nil)
      # Allow unauthenticated for testing, but log it
      user = context[:current_user]
      Rails.logger.info("[AnalyzeVideo] Request from user: #{user&.id || 'anonymous'}")

      unless VideoAnalysisService.api_configured?
        return {
          success: false,
          rep_count: nil,
          form_score: nil,
          exercise_detected: nil,
          issues: nil,
          feedback: nil,
          error: "Video analysis API is not configured"
        }
      end

      result = VideoAnalysisService.analyze_video(
        video_url: video_url,
        exercise_type: exercise_type
      )

      if result[:success]
        {
          success: true,
          rep_count: result[:rep_count],
          form_score: result[:form_score],
          exercise_detected: result[:exercise_type],
          issues: result[:issues],
          feedback: result[:feedback],
          error: nil
        }
      else
        {
          success: false,
          rep_count: nil,
          form_score: nil,
          exercise_detected: nil,
          issues: nil,
          feedback: nil,
          error: result[:error]
        }
      end
    rescue StandardError => e
      Rails.logger.error("[AnalyzeVideo] Error: #{e.message}")
      {
        success: false,
        rep_count: nil,
        form_score: nil,
        exercise_detected: nil,
        issues: nil,
        feedback: nil,
        error: e.message
      }
    end
  end
end
