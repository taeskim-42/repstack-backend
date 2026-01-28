# frozen_string_literal: true

# AI Trainer module - handles workout routine generation and level management
module AiTrainer
  class << self
    # Generate routine using CreativeRoutineGenerator (RAG + LLM)
    # Always uses AI-based creative generation for personalized routines
    # @param dynamic [Boolean] Ignored - kept for backwards compatibility
    def generate_routine(user:, day_of_week: nil, condition_inputs: {}, recent_feedbacks: nil, dynamic: false, preferences: {}, goal: nil)
      # Always use CreativeRoutineGenerator via RoutineService
      RoutineService.generate(
        user: user,
        day_of_week: day_of_week,
        condition: condition_inputs.presence,
        recent_feedbacks: recent_feedbacks,
        goal: goal
      )
    end

    # Alias for backwards compatibility
    def generate_dynamic_routine(user:, day_of_week: nil, condition_inputs: {}, recent_feedbacks: nil, preferences: {}, goal: nil)
      generate_routine(
        user: user,
        day_of_week: day_of_week,
        condition_inputs: condition_inputs,
        recent_feedbacks: recent_feedbacks,
        goal: goal
      )
    end

    def generate_level_test(user:)
      service = LevelTestService.new(user: user)
      service.generate_test
    end

    def evaluate_level_test(user:, test_results:)
      service = LevelTestService.new(user: user)
      service.evaluate_results(test_results)
    end

    def check_test_eligibility(user:)
      service = LevelTestService.new(user: user)
      service.eligible_for_test?
    end

    def constants
      Constants
    end

    def dynamic_routine_config
      DynamicRoutineConfig
    end
  end
end

require_relative "ai_trainer/constants"
require_relative "ai_trainer/dynamic_routine_config"
require_relative "ai_trainer/routine_generator"
require_relative "ai_trainer/dynamic_routine_generator"
require_relative "ai_trainer/level_test_service"
require_relative "ai_trainer/condition_service"
require_relative "ai_trainer/feedback_service"
require_relative "ai_trainer/chat_service"
require_relative "ai_trainer/routine_service"
