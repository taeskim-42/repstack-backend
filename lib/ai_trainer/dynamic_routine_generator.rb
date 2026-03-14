# frozen_string_literal: true

require_relative "constants"
require_relative "dynamic_routine_config"
require_relative "dynamic_routine/context_builder"
require_relative "dynamic_routine/response_parser"

module AiTrainer
  # Generates workout routines dynamically using AI
  # Instead of fixed programs, it combines:
  # - Exercise pool (from DB)
  # - Split rules
  # - Training methods
  # - User context (level, condition, feedback)
  class DynamicRoutineGenerator
    include Constants
    include DynamicRoutineConfig
    include DynamicRoutine::ContextBuilder
    include DynamicRoutine::ResponseParser

    attr_reader :user, :level, :day_of_week, :condition_score, :adjustment,
                :condition_inputs, :recent_feedbacks, :preferences, :goal, :target_muscles

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || user.user_profile&.level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0 # Sunday -> Monday
      @day_of_week = 5 if @day_of_week > 5 # Weekend -> Friday
      @condition_score = 3.0
      @adjustment = Constants::CONDITION_ADJUSTMENTS[:good]
      @condition_inputs = {}
      @recent_feedbacks = []
      @preferences = default_preferences
      @goal = nil
      @target_muscles = []
    end

    # Set user preferences
    def with_preferences(prefs)
      @preferences = default_preferences.merge(prefs.symbolize_keys)
      self
    end

    # Set condition from user input
    def with_condition(condition_inputs)
      @condition_inputs = condition_inputs
      @condition_score = Constants.calculate_condition_score(condition_inputs)
      @adjustment = Constants.adjustment_for_condition_score(@condition_score)
      self
    end

    # Set recent feedbacks for personalization
    def with_feedbacks(feedbacks)
      @recent_feedbacks = feedbacks || []
      self
    end

    # Set training goal
    def with_goal(goal)
      @goal = goal
      @target_muscles = extract_target_muscles(goal) if goal.present?
      if @target_muscles.present?
        @preferences[:focus_muscles] = (@preferences[:focus_muscles] || []) + @target_muscles
      end
      self
    end

    # Generate a dynamic routine
    def generate
      training_focus = determine_training_focus
      available_exercises = fetch_available_exercises(training_focus)
      prompt = build_generation_prompt(training_focus, available_exercises)
      ai_response = generate_with_ai(prompt)
      routine = parse_ai_response(ai_response, available_exercises)
      enriched_routine = enrich_with_knowledge(routine)
      build_routine_response(enriched_routine, training_focus)
    rescue StandardError => e
      Rails.logger.error("DynamicRoutineGenerator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      { success: false, error: "루틴 생성 실패: #{e.message}" }
    end

    private

    def default_preferences
      {
        split_type: :fitness_factor_based,
        available_equipment: %w[none shark_rack dumbbell cable machine barbell],
        workout_duration_minutes: 45,
        exercises_per_workout: 4..6,
        preferred_training_methods: [ :standard, :bpm, :tabata ],
        avoid_exercises: [],
        focus_muscles: []
      }
    end

    # Determine what to train today based on split and day
    def determine_training_focus
      split_type = @preferences[:split_type]
      config = DynamicRoutineConfig::SPLIT_TYPES[split_type]

      case split_type
      when :fitness_factor_based
        day_name = %w[sunday monday tuesday wednesday thursday friday saturday][@day_of_week]
        day_config = config[:schedule][day_name.to_sym]

        {
          type: :fitness_factor,
          fitness_factor: day_config[:factor],
          fitness_factor_korean: day_config[:korean],
          muscle_groups: nil,
          training_method: recommended_method_for_factor(day_config[:factor])
        }
      when :full_body
        {
          type: :full_body,
          fitness_factor: :general,
          muscle_groups: config[:muscle_groups_per_day],
          training_method: :standard
        }
      else
        schedule = DynamicRoutineConfig.build_schedule(split_type, @day_of_week)
        {
          type: :split,
          split_type: split_type,
          muscle_groups: schedule,
          training_method: :standard
        }
      end
    end

    def recommended_method_for_factor(factor)
      case factor
      when :strength then :bpm
      when :muscular_endurance then :fill_target
      when :sustainability then :bpm
      when :cardiovascular then :tabata
      when :power then :standard
      else :standard
      end
    end

    def generate_with_ai(prompt)
      response = LlmGateway.chat(prompt: prompt, task: :routine_generation)
      raise "AI 응답 실패: #{response[:error]}" unless response[:success]

      response[:content]
    end

    def build_routine_response(routine, training_focus)
      day_info = Constants::WEEKLY_STRUCTURE[@day_of_week]

      {
        success: true,
        routine_id: generate_routine_id,
        generated_at: Time.current.iso8601,
        generation_type: "dynamic",
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        tier_korean: Constants::LEVELS[@level][:korean_tier],
        day_of_week: @day_of_week,
        day_korean: day_info[:korean],
        training_focus: training_focus,
        condition: {
          score: @condition_score.round(2),
          status: @adjustment[:korean],
          volume_modifier: @adjustment[:volume_modifier],
          intensity_modifier: @adjustment[:intensity_modifier]
        },
        exercises: routine[:exercises],
        warmup_suggestion: routine[:warmup_suggestion],
        cooldown_suggestion: routine[:cooldown_suggestion],
        coach_note: routine[:coach_note],
        estimated_duration_minutes: @preferences[:workout_duration_minutes],
        preferences_used: @preferences.slice(:split_type, :available_equipment)
      }
    end

    def generate_routine_id
      "DRT-#{@level}-D#{@day_of_week}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end

    def extract_target_muscles(goal_text)
      return [] unless goal_text.present?

      muscle_keywords = {
        "가슴" => "chest", "chest" => "chest",
        "등" => "back", "back" => "back",
        "어깨" => "shoulder", "shoulder" => "shoulder",
        "팔" => "arm", "이두" => "arm", "삼두" => "arm", "arm" => "arm",
        "복근" => "core", "코어" => "core", "core" => "core",
        "하체" => "leg", "다리" => "leg", "leg" => "leg",
        "엉덩이" => "glutes", "힙" => "glutes", "glutes" => "glutes"
      }

      found_muscles = []
      goal_lower = goal_text.downcase

      muscle_keywords.each do |keyword, muscle|
        found_muscles << muscle if goal_lower.include?(keyword.downcase) && !found_muscles.include?(muscle)
      end

      found_muscles
    end
  end
end
