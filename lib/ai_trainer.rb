# frozen_string_literal: true

# AI Trainer module - handles workout routine generation and level management
module AiTrainer
  class << self
    def generate_routine(user:, day_of_week: nil, condition_inputs: {}, recent_feedbacks: nil)
      generator = RoutineGenerator.new(user: user, day_of_week: day_of_week)
      generator.with_condition(condition_inputs) if condition_inputs.present?
      generator.with_feedbacks(recent_feedbacks) if recent_feedbacks.present?
      generator.generate
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
  end
end

require_relative "ai_trainer/constants"
require_relative "ai_trainer/routine_generator"
require_relative "ai_trainer/level_test_service"
require_relative "ai_trainer/condition_service"
require_relative "ai_trainer/feedback_service"
require_relative "ai_trainer/chat_service"
require_relative "ai_trainer/routine_service"
