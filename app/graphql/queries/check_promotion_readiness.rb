# frozen_string_literal: true

module Queries
  class CheckPromotionReadiness < BaseQuery
    description "Check if user is ready for level promotion based on estimated 1RM"

    type Types::PromotionReadinessType, null: false

    def resolve
      return guest_response unless current_user
      return profile_required_response unless current_user.user_profile

      result = AiTrainer::LevelTestService.evaluate_promotion(user: current_user)

      {
        eligible: result[:eligible],
        current_level: result[:current_level],
        target_level: result[:target_level],
        estimated_1rms: format_1rms(result[:estimated_1rms]),
        required_1rms: format_1rms(result[:required_1rms]),
        exercise_results: format_exercise_results(result[:exercise_results]),
        ai_feedback: result[:ai_feedback],
        recommendation: result[:recommendation].to_s
      }
    end

    private

    def guest_response
      {
        eligible: false,
        current_level: 1,
        target_level: 2,
        estimated_1rms: nil,
        required_1rms: nil,
        exercise_results: [],
        ai_feedback: "로그인이 필요합니다.",
        recommendation: "login_required"
      }
    end

    def profile_required_response
      {
        eligible: false,
        current_level: 1,
        target_level: 2,
        estimated_1rms: nil,
        required_1rms: nil,
        exercise_results: [],
        ai_feedback: "프로필 설정이 필요합니다.",
        recommendation: "profile_required"
      }
    end

    def format_1rms(data)
      return nil unless data

      {
        bench: data[:bench]&.round(1),
        squat: data[:squat]&.round(1),
        deadlift: data[:deadlift]&.round(1)
      }
    end

    def format_exercise_results(results)
      return [] unless results

      results.map do |exercise_type, data|
        {
          exercise_type: exercise_type.to_s,
          status: data[:status].to_s,
          estimated_1rm: data[:estimated_1rm],
          required: data[:required],
          surplus: data[:surplus],
          gap: data[:gap],
          message: data[:message]
        }
      end
    end
  end
end
