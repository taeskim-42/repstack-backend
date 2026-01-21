# frozen_string_literal: true

require_relative "constants"
require_relative "routine_generator"

module AiTrainer
  # Wrapper service for routine generation
  # Used by ChatService for the GENERATE_ROUTINE intent
  class RoutineService
    class << self
      def generate(user:, day_of_week: nil, condition: nil, recent_feedbacks: nil)
        new(user: user).generate(
          day_of_week: day_of_week,
          condition: condition,
          recent_feedbacks: recent_feedbacks
        )
      end
    end

    def initialize(user:)
      @user = user
    end

    def generate(day_of_week: nil, condition: nil, recent_feedbacks: nil)
      generator = RoutineGenerator.new(user: @user, day_of_week: day_of_week)

      # Apply condition if provided
      generator.with_condition(condition) if condition.present?

      # Apply recent feedbacks for personalization
      generator.with_feedbacks(recent_feedbacks) if recent_feedbacks.present?

      # Generate the routine
      result = generator.generate

      return nil unless result.is_a?(Hash) && result[:routine_id]

      # Add feedback context to notes if feedbacks provided
      if recent_feedbacks.present?
        result[:notes] ||= []
        result[:notes] << format_feedback_context(recent_feedbacks)
      end

      result
    rescue StandardError => e
      Rails.logger.error("RoutineService error: #{e.message}")
      nil
    end

    private

    def format_feedback_context(feedbacks)
      return nil if feedbacks.empty?

      feedback_notes = feedbacks.first(3).map do |fb|
        "- #{fb.feedback_type}: #{fb.feedback.truncate(50)}"
      end

      "최근 피드백 반영: #{feedback_notes.join(', ')}"
    end
  end
end
