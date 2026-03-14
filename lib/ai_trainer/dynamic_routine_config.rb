# frozen_string_literal: true

require_relative "data/split_types"
require_relative "data/training_parameters"

module AiTrainer
  # Configuration for dynamic routine generation
  # Defines split types, training methods, and variable options
  module DynamicRoutineConfig
    include Data::SplitTypes
    include Data::TrainingParameters

    # Re-export constants so existing callers continue to work
    SPLIT_TYPES         = Data::SplitTypes::SPLIT_TYPES
    TRAINING_METHODS    = Data::TrainingParameters::DYNAMIC_TRAINING_METHODS
    SET_SCHEMES         = Data::TrainingParameters::SET_SCHEMES
    REP_SCHEMES         = Data::TrainingParameters::REP_SCHEMES
    ROM_OPTIONS         = Data::TrainingParameters::ROM_OPTIONS
    REST_PATTERNS       = Data::TrainingParameters::REST_PATTERNS

    # ============================================================
    # HELPER METHODS
    # ============================================================
    class << self
      def split_for_level(level)
        SPLIT_TYPES.select do |_key, config|
          config[:suitable_for_levels].include?(level)
        end.keys
      end

      def training_methods_for_exercise(exercise)
        methods = [ :standard ]
        methods << :bpm if exercise.bpm_compatible
        methods << :tabata if exercise.tabata_compatible
        methods << :dropset if exercise.dropset_compatible
        methods << :superset if exercise.superset_compatible
        methods << :fill_target
        methods
      end

      def rep_scheme_for_fitness_factor(factor)
        case factor.to_sym
        when :strength then REP_SCHEMES[:strength]
        when :power then REP_SCHEMES[:power]
        when :muscular_endurance then REP_SCHEMES[:endurance]
        else REP_SCHEMES[:hypertrophy]
        end
      end

      def rest_for_training_method(method)
        config = TRAINING_METHODS[method.to_sym]
        return 60 unless config

        case config[:rest_pattern]
        when :fixed_interval then config[:rest_seconds]
        when :minimal then 10
        when :after_pair, :after_circuit then 90
        else 60
        end
      end

      def build_schedule(split_type, day_of_week)
        config = SPLIT_TYPES[split_type.to_sym]
        return nil unless config

        case split_type.to_sym
        when :full_body
          config[:muscle_groups_per_day]
        when :fitness_factor_based
          day_name = %w[sunday monday tuesday wednesday thursday friday saturday][day_of_week]
          config[:schedule][day_name.to_sym]
        else
          schedule_keys = config[:schedule].keys
          current_day = schedule_keys[(day_of_week - 1) % schedule_keys.length]
          config[:schedule][current_day]
        end
      end
    end
  end
end
