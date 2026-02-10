# frozen_string_literal: true

module Internal
  class FeedbacksController < BaseController
    # POST /internal/feedbacks/submit
    def submit
      feedback_text = params[:feedback_text]
      feedback_type = (params[:feedback_type] || "specific").to_sym
      return render_error("피드백 내용이 필요합니다.") if feedback_text.blank?

      profile = @user.user_profile
      return render_error("프로필이 없습니다.") unless profile

      factors = profile.fitness_factors || {}

      # Store feedback history
      feedbacks = factors["workout_feedbacks"] || []
      feedbacks << {
        date: Date.current.to_s,
        type: feedback_type.to_s,
        text: feedback_text,
        recorded_at: Time.current.iso8601
      }
      factors["workout_feedbacks"] = feedbacks.last(30)

      # Calculate intensity adjustment
      adjustment = factors["intensity_adjustment"] || 0.0
      case feedback_type
      when :too_easy
        adjustment = [adjustment + 0.05, 0.3].min
      when :too_hard
        adjustment = [adjustment - 0.05, -0.3].max
      end

      factors["intensity_adjustment"] = adjustment
      factors["last_feedback_at"] = Time.current.iso8601
      profile.update!(fitness_factors: factors)

      render_success(
        feedback_type: feedback_type.to_s,
        intensity_adjustment: adjustment
      )
    end
  end
end
