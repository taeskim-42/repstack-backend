# frozen_string_literal: true

module AiTrainer
  module Shared
    module DayNames
      DAY_NAMES_KR = %w[일 월 화 수 목 금 토].freeze
      DAY_NAMES_EN = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

      def day_name_korean(day_index)
        "#{DAY_NAMES_KR[day_index]}요일"
      end

      def day_name_english(day_index)
        DAY_NAMES_EN[day_index] || "wednesday"
      end
    end
  end
end
