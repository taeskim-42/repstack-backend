# frozen_string_literal: true

module ChatRoutineFormatter
  module AdjustmentApplier
    private

    # Adjust routine exercises based on feedback history and current condition.
    # Returns modified routine_data hash (does NOT mutate original).
    def apply_routine_adjustments(routine_data, condition_modifier: 1.0)
      profile = user.user_profile
      intensity_adj = profile&.fitness_factors&.dig("intensity_adjustment") || 0.0

      # Combined multiplier: feedback history * today's condition
      multiplier = condition_modifier * (1.0 + intensity_adj)

      return routine_data if (multiplier - 1.0).abs < 0.02 # Skip trivial adjustments

      adjusted = routine_data.dup
      adjusted[:exercises] = routine_data[:exercises].map do |ex|
        adj_ex = ex.dup

        # Adjust reps proportionally
        base_reps = ex[:reps] || 10
        adj_ex[:reps] = [ (base_reps * multiplier).round, 1 ].max

        # Adjust weight proportionally (round to nearest 2.5kg)
        base_weight = ex[:target_weight_kg] || ex[:weight]
        if base_weight.is_a?(Numeric) && base_weight > 0
          weight_key = ex.key?(:target_weight_kg) ? :target_weight_kg : :weight
          adj_ex[weight_key] = (base_weight * multiplier / 2.5).round * 2.5
        end

        # Adjust sets only for significant changes (|delta| >= 0.15)
        if (multiplier - 1.0).abs >= 0.15
          base_sets = ex[:sets] || 3
          adj_ex[:sets] = if multiplier > 1.0
            [ base_sets + 1, 6 ].min
          else
            [ base_sets - 1, 1 ].max
          end
        end

        adj_ex
      end

      adjusted[:adjusted] = true
      adjusted[:adjustment_multiplier] = multiplier.round(2)
      adjusted
    end
  end
end
