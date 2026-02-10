# frozen_string_literal: true

module Internal
  class ProgramsController < BaseController
    # GET /internal/programs/explain
    def explain
      profile = @user.user_profile
      return render_error("프로필이 없습니다.") unless profile
      return render_error("온보딩 미완료") unless profile.onboarding_completed_at

      program = @user.active_training_program
      consultation_data = profile.fitness_factors&.dig("collected_data") || {}

      data = {
        user: {
          name: @user.name,
          level: profile.numeric_level || 1,
          tier: profile.tier || "beginner",
          goal: profile.fitness_goal,
          frequency: consultation_data["frequency"],
          environment: consultation_data["environment"],
          injuries: consultation_data["injuries"],
          focus_areas: consultation_data["focus_areas"]
        },
        program: program ? {
          name: program.name,
          current_week: program.current_week,
          total_weeks: program.total_weeks,
          phase: program.current_phase,
          progress_percentage: program.progress_percentage,
          split_schedule: program.split_schedule,
          weekly_plan: program.weekly_plan
        } : nil
      }

      render_success(data)
    end
  end
end
