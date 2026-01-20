# frozen_string_literal: true

module Mutations
  class SubmitFeedbackFromVoice < BaseMutation
    description "Submit workout feedback via voice input and get AI analysis"

    argument :voice_text, String, required: true,
      description: "Voice input text describing workout feedback"
    argument :routine_id, ID, required: false,
      description: "Optional routine ID for context"

    field :success, Boolean, null: false
    field :feedback, Types::VoiceFeedbackResultType, null: true
    field :analysis, Types::FeedbackAnalysisType, null: true
    field :interpretation, String, null: true
    field :error, String, null: true

    def resolve(voice_text:, routine_id: nil)
      authenticate_user!

      # AI analyzes voice feedback and returns insights + recommendations
      result = AiTrainerService.analyze_feedback_from_voice(voice_text, routine_id: routine_id)

      unless result[:success]
        return {
          success: false,
          feedback: nil,
          analysis: nil,
          interpretation: nil,
          error: result[:error]
        }
      end

      # Save feedback record
      feedback_record = save_feedback(result[:feedback], routine_id)

      {
        success: true,
        feedback: {
          id: feedback_record&.id,
          rating: result[:feedback][:rating],
          feedback_type: result[:feedback][:feedback_type],
          summary: result[:feedback][:summary],
          would_recommend: result[:feedback][:would_recommend]
        },
        analysis: {
          insights: result[:insights],
          adaptations: result[:adaptations],
          next_workout_recommendations: result[:next_workout_recommendations]
        },
        interpretation: result[:interpretation],
        error: nil
      }
    end

    private

    def save_feedback(feedback_data, routine_id)
      WorkoutFeedback.create!(
        user: current_user,
        routine_id: routine_id,
        feedback_type: feedback_data[:feedback_type],
        rating: feedback_data[:rating],
        feedback: feedback_data[:summary],
        would_recommend: feedback_data[:would_recommend]
      )
    rescue StandardError => e
      Rails.logger.error("Failed to save voice feedback: #{e.message}")
      nil
    end
  end
end
