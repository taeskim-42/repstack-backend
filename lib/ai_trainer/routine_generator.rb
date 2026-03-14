# frozen_string_literal: true

require_relative "constants"
require_relative "workout_programs"
require_relative "routine_generator/exercise_builder"
require_relative "routine_generator/knowledge_enricher"

module AiTrainer
  # Generates workout routines using structured WorkoutPrograms
  # Hybrid approach:
  #   - Foundation: Fixed exercises from WorkoutPrograms (Excel program)
  #   - Variables: Adjusted based on condition (sets, reps, weight, etc.)
  #   - Enrichment: YouTube knowledge for tips and instructions
  class RoutineGenerator
    include Constants
    include RoutineGenerator::ExerciseBuilder
    include RoutineGenerator::KnowledgeEnricher

    attr_reader :user, :level, :week, :day_of_week, :condition_score, :adjustment, :condition_inputs, :recent_feedbacks

    def initialize(user:, day_of_week: nil, week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || user.user_profile&.level || 1
      @week = week || calculate_current_week
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0 # Sunday -> Monday
      @day_of_week = 5 if @day_of_week > 5 # Weekend -> Friday
      @condition_score = 3.0
      @adjustment = Constants::CONDITION_ADJUSTMENTS[:good]
      @condition_inputs = {}
      @recent_feedbacks = []
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

    # Generate a complete routine using structured program + enrichment
    def generate
      workout = WorkoutPrograms.get_workout(level: @level, week: @week, day: @day_of_week)

      unless workout
        return { success: false, error: "해당 주차/요일의 운동 프로그램을 찾을 수 없습니다." }
      end

      exercises = build_exercises(workout)
      enriched_exercises = enrich_with_knowledge(exercises, workout[:training_type])

      build_routine_response(workout, enriched_exercises)
    rescue StandardError => e
      Rails.logger.error("RoutineGenerator error: #{e.message}")
      { success: false, error: "루틴 생성 실패: #{e.message}" }
    end

    private

    # Calculate which week the user is on based on their start date
    def calculate_current_week
      start_date = @user.user_profile&.onboarding_completed_at || @user.created_at
      weeks_elapsed = ((Time.current - start_date) / 1.week).floor
      program = WorkoutPrograms.program_for_level(@level)
      max_weeks = program[:weeks]

      # Cycle through weeks (1-4, then repeat)
      (weeks_elapsed % max_weeks) + 1
    end

    # Build the final routine response
    def build_routine_response(workout, exercises)
      program = WorkoutPrograms.program_for_level(@level)
      training_type_info = WorkoutPrograms.training_type_info(workout[:training_type])
      day_info = Constants::WEEKLY_STRUCTURE[@day_of_week]
      fitness_factor = day_info[:fitness_factor]
      fitness_factor_info = Constants::FITNESS_FACTORS[fitness_factor]

      {
        routine_id: generate_routine_id,
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        tier_korean: program[:korean],
        week: @week,
        day_of_week: @day_of_week,
        day_korean: day_info[:korean],
        fitness_factor: fitness_factor.to_s,
        fitness_factor_korean: fitness_factor_info[:korean],
        training_type: workout[:training_type].to_s,
        training_type_korean: training_type_info[:korean],
        training_type_description: training_type_info[:description],
        condition: {
          score: @condition_score.round(2),
          status: @adjustment[:korean],
          volume_modifier: @adjustment[:volume_modifier],
          intensity_modifier: @adjustment[:intensity_modifier]
        },
        exercises: exercises,
        purpose: workout[:purpose],
        estimated_duration_minutes: estimate_duration(exercises, workout[:training_type]),
        notes: build_notes(workout, training_type_info)
      }
    end

    def estimate_duration(exercises, training_type)
      base_time = case training_type
      when :cardiovascular then 20
      when :muscular_endurance then 50
      else 45
      end

      exercise_count = exercises.length
      base_time + (exercise_count - 4) * 5
    end

    def build_notes(workout, training_type_info)
      notes = []

      notes << "#{@week}주차 #{training_type_info[:korean]} 훈련입니다."
      notes << training_type_info[:description]

      if @adjustment[:volume_modifier] < 1.0
        notes << "컨디션을 고려하여 운동량을 조절했습니다."
      elsif @adjustment[:volume_modifier] > 1.0
        notes << "컨디션이 좋으니 조금 더 도전해보세요!"
      end

      notes << workout[:purpose] if workout[:purpose].present?

      notes
    end

    def generate_routine_id
      "RT-#{@level}-W#{@week}-D#{@day_of_week}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end

    # generate_fallback_id is used by ExerciseBuilder (included above)
    def generate_fallback_id(order)
      "TEMP-#{order}-#{SecureRandom.hex(4)}"
    end
  end
end
