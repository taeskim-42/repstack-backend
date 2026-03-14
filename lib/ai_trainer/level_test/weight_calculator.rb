# frozen_string_literal: true

module AiTrainer
  module LevelTest
    # Calculates required weights for the 3 big lifts based on height and criteria ratios.
    module WeightCalculator
      # Exercise name variants for 3 big lifts (used for workout history matching)
      EXERCISE_MAPPINGS = {
        bench: %w[벤치프레스 벤치 프레스 bench\ press benchpress],
        squat: %w[스쿼트 바벨\ 스쿼트 squat barbell\ squat],
        deadlift: %w[데드리프트 데드 deadlift]
      }.freeze

      # Calculate required 1RM weight for a given exercise type
      # Base weight derived from height; multiplied by the criteria ratio
      def calculate_required_weight(criteria, exercise_type, height)
        ratio_key = "#{exercise_type}_ratio".to_sym
        ratio = criteria[ratio_key] || 1.0
        base_weight = case exercise_type
        when :bench then height - 100
        when :squat then height - 100 + 20
        when :deadlift then height - 100 + 40
        else height - 100
        end

        (base_weight * ratio).round(1)
      end
    end
  end
end
