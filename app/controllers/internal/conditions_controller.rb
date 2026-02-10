# frozen_string_literal: true

module Internal
  class ConditionsController < BaseController
    # POST /internal/conditions/check
    def check
      condition_text = params[:condition_text]
      return render_error("컨디션 텍스트가 필요합니다.") if condition_text.blank?

      result = AiTrainer::ConditionService.analyze_from_voice(
        user: @user,
        text: condition_text
      )

      unless result[:success]
        return render_error(result[:error] || "컨디션 분석 실패")
      end

      condition = result[:condition]

      # Save condition log
      @user.condition_logs.create!(
        date: Date.current,
        energy_level: condition[:energy_level] || 3,
        stress_level: condition[:stress_level] || 3,
        sleep_quality: condition[:sleep_quality] || 3,
        motivation: condition[:motivation] || 3,
        soreness: condition[:soreness] || {},
        available_time: condition[:available_time] || 60,
        notes: "Agent API"
      )

      render_success(
        condition: condition,
        intensity_modifier: result[:intensity_modifier],
        interpretation: result[:interpretation],
        adaptations: result[:adaptations]
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Internal::ConditionsController] Condition log save failed: #{e.message}")
      # Still return the analysis even if log save fails
      render_success(
        condition: result[:condition],
        intensity_modifier: result[:intensity_modifier]
      )
    end
  end
end
