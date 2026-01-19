# frozen_string_literal: true

module Mutations
  class SubmitFeedback < BaseMutation
    description "Submit workout feedback and get AI analysis"

    argument :input, Types::FeedbackInputType, required: true,
      description: "Feedback input data"

    field :success, Boolean, null: false
    field :feedback, Types::FeedbackSummaryType, null: true
    field :analysis, Types::FeedbackAnalysisType, null: true
    field :error, String, null: true

    def resolve(input:)
      authenticate_user!

      input_hash = input.to_h.deep_transform_keys { |k| k.to_s.underscore.to_sym }

      # Save feedback
      feedback_record = WorkoutFeedback.create!(
        user: current_user,
        workout_record_id: input_hash[:workout_record_id],
        routine_id: input_hash[:routine_id],
        feedback_type: input_hash[:feedback_type],
        rating: input_hash[:rating],
        feedback: input_hash[:feedback],
        suggestions: input_hash[:suggestions],
        would_recommend: input_hash[:would_recommend]
      )

      # Get AI analysis
      analysis_result = AiTrainerService.analyze_feedback(input_hash)

      if analysis_result[:success]
        {
          success: true,
          feedback: {
            id: feedback_record.id,
            rating: feedback_record.rating,
            feedback_type: feedback_record.feedback_type
          },
          analysis: {
            insights: analysis_result[:insights],
            adaptations: analysis_result[:adaptations],
            next_workout_recommendations: analysis_result[:next_workout_recommendations]
          },
          error: nil
        }
      else
        {
          success: true,
          feedback: {
            id: feedback_record.id,
            rating: feedback_record.rating,
            feedback_type: feedback_record.feedback_type
          },
          analysis: nil,
          error: analysis_result[:error]
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, feedback: nil, analysis: nil, error: e.message }
    rescue StandardError => e
      Rails.logger.error("SubmitFeedback error: #{e.message}")
      { success: false, feedback: nil, analysis: nil, error: "Failed to submit feedback" }
    end
  end
end
