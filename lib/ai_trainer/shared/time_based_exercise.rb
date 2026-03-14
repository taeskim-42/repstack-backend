# frozen_string_literal: true

module AiTrainer
  module Shared
    module TimeBasedExercise
      TIME_BASED_KEYWORDS = %w[플랭크 홀드 월싯 wall-sit 데드행 버티기 스태틱 static isometric].freeze

      def time_based_exercise?(name)
        return false if name.blank?

        name_lower = name.downcase
        TIME_BASED_KEYWORDS.any? { |keyword| name_lower.include?(keyword) }
      end
    end
  end
end
