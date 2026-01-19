# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Generates workout routines using variable combinations
  # Creates infinite variations based on fitness factors, level, and condition
  class RoutineGenerator
    include Constants

    attr_reader :user, :level, :day_of_week, :condition_score, :adjustment

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || user.user_profile&.level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0 # Sunday -> Monday
      @day_of_week = 5 if @day_of_week > 5 # Weekend -> Friday
      @condition_score = 3.0
      @adjustment = Constants::CONDITION_ADJUSTMENTS[:good]
    end

    # Set condition from user input
    def with_condition(condition_inputs)
      @condition_score = Constants.calculate_condition_score(condition_inputs)
      @adjustment = Constants.adjustment_for_condition_score(@condition_score)
      self
    end

    # Generate a complete routine
    def generate
      fitness_factor = Constants.fitness_factor_for_day(@day_of_week)
      training_method = Constants.training_method_for_factor(fitness_factor)
      exercises = select_exercises(fitness_factor)

      {
        routine_id: generate_routine_id,
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        day_of_week: Constants::WEEKLY_STRUCTURE[@day_of_week][:day],
        day_korean: Constants::WEEKLY_STRUCTURE[@day_of_week][:korean],
        fitness_factor: fitness_factor,
        fitness_factor_korean: Constants::FITNESS_FACTORS[fitness_factor][:korean],
        training_method: training_method,
        training_method_info: Constants::TRAINING_METHODS[training_method],
        condition: {
          score: @condition_score.round(2),
          status: @adjustment[:korean],
          volume_modifier: @adjustment[:volume_modifier],
          intensity_modifier: @adjustment[:intensity_modifier]
        },
        estimated_duration_minutes: calculate_duration(exercises, fitness_factor),
        exercises: exercises,
        notes: generate_notes(fitness_factor)
      }
    end

    private

    def generate_routine_id
      "RT-#{@level}-#{@day_of_week}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end

    def select_exercises(fitness_factor)
      muscle_groups = select_muscle_groups_for_day
      exercises = []

      muscle_groups.each_with_index do |muscle_group, index|
        available = Constants.exercises_for_muscle(muscle_group)
        selected = select_exercise_with_variation(available, muscle_group)

        next unless selected

        exercise_config = build_exercise_config(
          selected,
          muscle_group,
          fitness_factor,
          index
        )
        exercises << exercise_config
      end

      # Add core exercise at the end
      add_core_exercise(exercises, fitness_factor)

      exercises
    end

    def select_muscle_groups_for_day
      case @day_of_week
      when 1, 4 # Monday, Thursday - Strength
        %i[chest back legs]
      when 2 # Tuesday - Muscular Endurance
        %i[chest back legs shoulders]
      when 3 # Wednesday - Sustainability
        %i[chest back legs]
      when 5 # Friday - Cardiovascular
        [:cardio]
      else
        %i[chest back legs]
      end
    end

    def select_exercise_with_variation(available, muscle_group)
      return nil if available.empty?

      # Filter by difficulty appropriate for level
      max_difficulty = case Constants.tier_for_level(@level)
                       when "beginner" then 2
                       when "intermediate" then 3
                       else 4
                       end

      suitable = available.select { |e| e[:difficulty] <= max_difficulty }
      suitable = available.take(3) if suitable.empty? # Fallback

      # Add randomness for variation
      suitable.sample
    end

    def build_exercise_config(exercise, muscle_group, fitness_factor, order)
      factor_config = Constants::FITNESS_FACTORS[fitness_factor]
      training_method = factor_config[:training_method]

      base_config = {
        order: order + 1,
        exercise_id: exercise[:id],
        exercise_name: exercise[:name],
        exercise_name_english: exercise[:english],
        target_muscle: muscle_group.to_s,
        target_muscle_korean: Constants::EXERCISES[muscle_group][:korean],
        equipment: exercise[:equipment]
      }

      # Add training-specific parameters
      case training_method
      when "fixed_sets_reps"
        add_strength_params(base_config, factor_config)
      when "total_reps_fill"
        add_endurance_params(base_config, factor_config)
      when "max_sets_at_fixed_reps"
        add_sustainability_params(base_config, factor_config)
      when "tabata"
        add_tabata_params(base_config)
      when "explosive"
        add_power_params(base_config, factor_config)
      end

      # Apply condition adjustments
      apply_condition_adjustments(base_config)

      # Add weight calculation for applicable exercises
      add_weight_info(base_config, exercise)

      base_config
    end

    def add_strength_params(config, factor_config)
      config[:sets] = apply_variation(3, 0.2)
      config[:reps] = 10
      config[:bpm] = factor_config[:typical_bpm]
      config[:rest_seconds] = factor_config[:typical_rest]
      config[:rest_type] = "time_based"
      config[:range_of_motion] = "full"
      config[:instructions] = "BPM에 맞춰 정확한 자세로 #{config[:sets]}세트 #{config[:reps]}회 수행"
    end

    def add_endurance_params(config, factor_config)
      total_target = apply_variation(50, 0.2)
      config[:target_total_reps] = total_target
      config[:sets] = "until_complete"
      config[:reps] = "max_per_set"
      config[:bpm] = factor_config[:typical_bpm]
      config[:rest_seconds] = factor_config[:typical_rest]
      config[:rest_type] = "time_based"
      config[:range_of_motion] = "full"
      config[:instructions] = "총 #{total_target}회를 채우세요. 세트당 최대 횟수 수행"
    end

    def add_sustainability_params(config, factor_config)
      config[:reps] = 10
      config[:sets] = "max_sustainable"
      config[:bpm] = factor_config[:typical_bpm]
      config[:rest_seconds] = factor_config[:typical_rest]
      config[:rest_type] = "time_based"
      config[:range_of_motion] = "full"
      config[:instructions] = "#{config[:reps]}회씩 몇 세트까지 지속 가능한지 측정"
    end

    def add_tabata_params(config)
      tabata = Constants::TRAINING_METHODS[:tabata]
      config[:work_seconds] = tabata[:work_duration]
      config[:rest_seconds] = tabata[:rest_duration]
      config[:rounds] = tabata[:rounds]
      config[:rest_type] = "fixed"
      config[:range_of_motion] = "short"
      config[:instructions] = "#{tabata[:work_duration]}초 운동 + #{tabata[:rest_duration]}초 휴식을 #{tabata[:rounds]}라운드"
    end

    def add_power_params(config, factor_config)
      config[:sets] = 5
      config[:reps] = apply_variation(5, 0.2)
      config[:bpm] = nil
      config[:rest_seconds] = factor_config[:typical_rest]
      config[:rest_type] = "heart_rate_based"
      config[:heart_rate_threshold] = 0.6
      config[:range_of_motion] = "medium"
      config[:instructions] = "최대 폭발력으로 수행, 심박수 회복 후 다음 세트"
    end

    def apply_condition_adjustments(config)
      return config if @adjustment.nil?

      # Adjust volume
      if config[:sets].is_a?(Integer)
        config[:sets] = (config[:sets] * @adjustment[:volume_modifier]).round
        config[:sets] = [config[:sets], 1].max
      end

      if config[:target_total_reps]
        config[:target_total_reps] = (config[:target_total_reps] * @adjustment[:volume_modifier]).round
      end

      # Adjust rest based on condition
      if config[:rest_seconds].is_a?(Integer) && @adjustment[:volume_modifier] < 1.0
        config[:rest_seconds] = (config[:rest_seconds] * 1.2).round
      end

      config
    end

    def add_weight_info(config, exercise)
      # Only calculate weight for barbell exercises
      if exercise[:equipment] == "barbell"
        height = @user.user_profile&.height
        return add_bodyweight_instruction(config, exercise) unless height

        weight_type = case config[:target_muscle]
                      when "chest" then :bench
                      when "back" then :deadlift
                      when "legs" then :squat
                      end

        if weight_type
          target_weight = Constants.calculate_target_weight(
            exercise_type: weight_type,
            height: height,
            level: @level
          )

          if target_weight
            config[:target_weight_kg] = (target_weight * @adjustment[:intensity_modifier]).round(1)
            config[:weight_description] = "목표 중량: #{config[:target_weight_kg]}kg"
            return config
          end
        end
      end

      # For non-barbell exercises, use bodyweight instruction
      add_bodyweight_instruction(config, exercise)
    end

    def add_bodyweight_instruction(config, exercise)
      config[:weight_description] = case exercise[:equipment]
                                    when "none"
                                      "체중"
                                    when "shark_rack"
                                      "10회 가능한 칸 위치"
                                    when "dumbbell"
                                      "10회 가능한 무게"
                                    when "cable"
                                      "10회 가능한 무게"
                                    when "machine"
                                      "10회 가능한 무게"
                                    when "pull_up_bar"
                                      "체중 (어시스트 가능)"
                                    else
                                      "적절한 무게 선택"
                                    end
      config
    end

    def add_core_exercise(exercises, fitness_factor)
      core_exercises = Constants.exercises_for_muscle(:core)
      selected = select_exercise_with_variation(core_exercises, :core)

      return unless selected

      config = build_exercise_config(
        selected,
        :core,
        fitness_factor,
        exercises.length
      )

      # Override core-specific settings
      config[:weight_description] = "체중"
      exercises << config
    end

    def calculate_duration(exercises, fitness_factor)
      return 20 if fitness_factor == :cardiovascular # Tabata is short

      total_seconds = exercises.sum do |ex|
        sets = ex[:sets].is_a?(Integer) ? ex[:sets] : 4
        reps = ex[:reps].is_a?(Integer) ? ex[:reps] : 10
        rest = ex[:rest_seconds] || 60

        work_time = sets * (reps * 2) # ~2 seconds per rep
        rest_time = (sets - 1) * rest

        work_time + rest_time
      end

      (total_seconds / 60.0).ceil + 5 # Add 5 min for warmup/transition
    end

    def apply_variation(base_value, variance_ratio)
      variance = (base_value * variance_ratio).round
      base_value + rand(-variance..variance)
    end

    def generate_notes(fitness_factor)
      notes = []

      notes << "오늘의 체력요인: #{Constants::FITNESS_FACTORS[fitness_factor][:korean]}"

      if @condition_score < 3.0
        notes << "컨디션이 좋지 않습니다. 무리하지 마세요."
      elsif @condition_score > 4.0
        notes << "컨디션이 좋습니다! 조금 더 도전해보세요."
      end

      tier = Constants.tier_for_level(@level)
      if tier == "beginner"
        notes << "자세에 집중하세요. 무게보다 폼이 중요합니다."
      end

      notes
    end
  end
end
