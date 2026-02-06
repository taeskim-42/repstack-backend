# frozen_string_literal: true

module Mutations
  class GenerateAiRoutine < BaseMutation
    description "Generate a personalized workout routine using AI trainer with infinite variations"

    argument :day_of_week, Integer, required: false, description: "Day of week (1-5, defaults to current day)"
    argument :condition, Types::ConditionInputType, required: false, description: "User's current condition"
    argument :dynamic, Boolean, required: false, default_value: false,
             description: "Use dynamic AI generation instead of fixed program"
    argument :preferences, Types::RoutinePreferencesInputType, required: false,
             description: "Preferences for dynamic routine generation"
    argument :goal, String, required: false,
             description: "Training goal (e.g., '등근육 키우고 싶음', '체중 감량')"

    field :success, Boolean, null: false
    field :routine, Types::AiRoutineType, null: true
    field :remaining_generations, Integer, null: true
    field :error, String, null: true

    def resolve(day_of_week: nil, condition: nil, dynamic: false, preferences: nil, goal: nil)
      authenticate_user!

      # Check rate limit
      rate_check = RoutineRateLimiter.check_and_increment!(
        user: current_user,
        action: :routine_generation
      )

      unless rate_check[:allowed]
        return {
          success: false,
          routine: nil,
          remaining_generations: 0,
          error: rate_check[:error]
        }
      end

      condition_inputs = condition&.to_h&.deep_transform_keys { |k| k.to_s.underscore.to_sym } || {}
      preference_inputs = preferences&.to_h&.deep_transform_keys { |k| k.to_s.underscore.to_sym } || {}

      # Fetch recent feedbacks for personalization
      recent_feedbacks = current_user.workout_feedbacks
                                     .order(created_at: :desc)
                                     .limit(5)

      routine = AiTrainer.generate_routine(
        user: current_user,
        day_of_week: day_of_week,
        condition_inputs: condition_inputs,
        recent_feedbacks: recent_feedbacks,
        dynamic: dynamic,
        preferences: preference_inputs,
        goal: goal
      )

      if routine.is_a?(Hash) && routine[:success] == false
        {
          success: false,
          routine: nil,
          remaining_generations: rate_check[:remaining],
          error: routine[:error]
        }
      else
        {
          success: true,
          routine: routine,
          remaining_generations: rate_check[:remaining],
          error: nil
        }
      end
    rescue NoMethodError => e
      Rails.logger.error("GenerateAiRoutine NoMethodError: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      { success: false, routine: nil, remaining_generations: rate_check&.dig(:remaining) || 0,
        error: "루틴 생성 중 오류가 발생했어요. 프로필 설정을 확인해주세요." }
    rescue StandardError => e
      Rails.logger.error("GenerateAiRoutine error: #{e.message}")
      { success: false, routine: nil, remaining_generations: rate_check&.dig(:remaining) || 0,
        error: "루틴 생성에 실패했어요. 잠시 후 다시 시도해주세요." }
    end
  end
end
