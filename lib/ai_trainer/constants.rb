# frozen_string_literal: true

require_relative "data/fitness_constants"
require_relative "data/exercise_catalog"
require_relative "data/training_constants"
require_relative "data/condition_constants"
require_relative "data/level_test_constants"

module AiTrainer
  module Constants
    include Data::FitnessConstants
    include Data::ExerciseCatalog
    include Data::TrainingConstants
    include Data::ConditionConstants
    include Data::LevelTestConstants

    # Re-export all constants so `include Constants` continues to work everywhere
    FITNESS_FACTORS    = Data::FitnessConstants::FITNESS_FACTORS
    LEVELS             = Data::FitnessConstants::LEVELS
    GRADES             = Data::FitnessConstants::GRADES
    FEEDBACK_CATEGORIES = Data::FitnessConstants::FEEDBACK_CATEGORIES

    EXERCISES          = Data::ExerciseCatalog::EXERCISES

    TRAINING_VARIABLES = Data::TrainingConstants::TRAINING_VARIABLES
    TRAINING_METHODS   = Data::TrainingConstants::TRAINING_METHODS
    WEEKLY_STRUCTURE   = Data::TrainingConstants::WEEKLY_STRUCTURE

    CONDITION_INPUTS   = Data::ConditionConstants::CONDITION_INPUTS
    CONDITION_ADJUSTMENTS = Data::ConditionConstants::CONDITION_ADJUSTMENTS

    LEVEL_TEST_CRITERIA = Data::LevelTestConstants::LEVEL_TEST_CRITERIA

    # Helper methods
    class << self
      def fitness_factor_for_day(day_number)
        WEEKLY_STRUCTURE.dig(day_number, :fitness_factor)
      end

      def level_info(level)
        LEVELS[level]
      end

      def tier_for_level(level)
        LEVELS.dig(level, :tier)
      end

      def weight_multiplier_for_level(level)
        LEVELS.dig(level, :weight_multiplier) || 1.0
      end

      def exercises_for_muscle(muscle_group)
        EXERCISES.dig(muscle_group.to_sym, :exercises) || []
      end

      def calculate_condition_score(inputs)
        total_weight = CONDITION_INPUTS.values.sum { |v| v[:weight] }
        weighted_sum = 0.0

        CONDITION_INPUTS.each do |key, config|
          value = inputs[key] || 3
          adjusted_value = %i[fatigue stress soreness].include?(key) ? (6 - value) : value
          weighted_sum += adjusted_value * config[:weight]
        end

        weighted_sum / total_weight
      end

      def adjustment_for_condition_score(score)
        CONDITION_ADJUSTMENTS.find { |_key, config| config[:score_range].include?(score) }&.last || CONDITION_ADJUSTMENTS[:good]
      end

      def calculate_target_weight(exercise_type:, height:, level:)
        formula = TRAINING_VARIABLES.dig(:weight, :formula, exercise_type.to_sym)
        return nil unless formula

        formula.call(height, level).round(2)
      end

      def training_method_for_factor(factor)
        TRAINING_METHODS.find { |_key, config| config[:applies_to].include?(factor.to_sym) }&.first
      end
    end
  end
end
