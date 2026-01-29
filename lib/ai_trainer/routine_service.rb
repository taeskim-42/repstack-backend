# frozen_string_literal: true

require_relative "constants"
require_relative "creative_routine_generator"
require_relative "tool_based_routine_generator"

module AiTrainer
  # Wrapper service for routine generation
  # Uses ToolBasedRoutineGenerator (LLM Tool Use) for creative, variable-aware routines
  # Falls back to CreativeRoutineGenerator if needed
  class RoutineService
    # Set to true to use the new Tool Use based generator
    USE_TOOL_BASED_GENERATOR = true

    class << self
      def generate(user:, day_of_week: nil, condition: nil, recent_feedbacks: nil, goal: nil)
        new(user: user).generate(
          day_of_week: day_of_week,
          condition: condition,
          recent_feedbacks: recent_feedbacks,
          goal: goal
        )
      end
    end

    def initialize(user:)
      @user = user
    end

    def generate(day_of_week: nil, condition: nil, recent_feedbacks: nil, goal: nil)
      result = if USE_TOOL_BASED_GENERATOR
                 generate_with_tool_based(day_of_week, condition, goal)
               else
                 generate_with_creative(day_of_week, condition, recent_feedbacks, goal)
               end

      return nil unless result.is_a?(Hash) && result[:routine_id]

      # Save to database
      save_routine_to_db(result)

      result
    rescue StandardError => e
      Rails.logger.error("RoutineService error: #{e.message}")
      # Fallback to creative generator if tool-based fails
      if USE_TOOL_BASED_GENERATOR
        Rails.logger.info("Falling back to CreativeRoutineGenerator")
        generate_with_creative(day_of_week, condition, recent_feedbacks, goal)
      end
    end

    private

    # New: Tool Use based generator (LLM decides which tools to call)
    def generate_with_tool_based(day_of_week, condition, goal)
      generator = ToolBasedRoutineGenerator.new(user: @user, day_of_week: day_of_week)

      generator.with_goal(goal) if goal.present?
      generator.with_condition(condition) if condition.present?

      generator.generate
    end

    # Legacy: Creative generator (pre-defined prompt with exercise pool)
    def generate_with_creative(day_of_week, condition, recent_feedbacks, goal)
      generator = CreativeRoutineGenerator.new(user: @user, day_of_week: day_of_week)

      generator.with_goal(goal) if goal.present?
      generator.with_condition(condition) if condition.present?

      if recent_feedbacks.present?
        preferences = extract_preferences_from_feedbacks(recent_feedbacks)
        generator.with_preferences(preferences)
      end

      generator.generate
    end

    private

    def extract_preferences_from_feedbacks(feedbacks)
      preferences = {
        avoid_exercises: [],
        preferred_exercises: [],
        intensity_preference: nil
      }

      feedbacks.each do |fb|
        case fb.feedback_type
        when "too_hard", "injury_risk"
          preferences[:avoid_exercises] << fb.exercise_name if fb.exercise_name
          preferences[:intensity_preference] = "lower"
        when "too_easy"
          preferences[:intensity_preference] = "higher"
        when "enjoyed"
          preferences[:preferred_exercises] << fb.exercise_name if fb.exercise_name
        end
      end

      preferences
    end

    def save_routine_to_db(result)
      routine = @user.workout_routines.create!(
        level: Constants.tier_for_level(result[:user_level]),
        week_number: calculate_week_number,
        day_number: result[:day_of_week],
        workout_type: result[:training_type],
        day_of_week: day_name(result[:day_of_week]),
        estimated_duration: result[:estimated_duration_minutes],
        generated_at: Time.current
      )

      result[:exercises].each do |ex|
        routine.routine_exercises.create!(
          exercise_name: ex[:exercise_name],
          order_index: ex[:order],
          sets: ex[:sets],
          reps: ex[:reps],
          target_muscle: ex[:target_muscle],
          rest_duration_seconds: ex[:rest_seconds] || 60,
          instructions: ex[:instructions],
          weight_suggestion: ex[:weight_description]
        )
      end

      result[:routine_id] = routine.id
      result[:db_routine] = routine
      result
    rescue StandardError => e
      Rails.logger.warn("Failed to save routine to DB: #{e.message}")
      result
    end

    def calculate_week_number
      start_date = @user.user_profile&.onboarding_completed_at || @user.created_at
      ((Time.current - start_date) / 1.week).floor + 1
    end

    def day_name(day)
      %w[sunday monday tuesday wednesday thursday friday saturday][day]
    end
  end
end
