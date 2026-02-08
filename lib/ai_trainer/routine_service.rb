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

      return nil unless result.is_a?(Hash)

      # Rest day: return directly without saving
      return result if result[:rest_day]

      return nil unless result[:routine_id]

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
      # day_of_week can be string ("wednesday") or integer (3)
      dow = result[:day_of_week]
      day_num = dow.is_a?(Integer) ? dow : day_index(dow)
      day_str = dow.is_a?(String) ? dow : day_name(dow)

      # Handle nil values with defaults
      level = Constants.tier_for_level(result[:user_level]) || "beginner"
      workout_type = result[:training_type] || result[:fitness_factor_korean] || "일반 훈련"
      duration = result[:estimated_duration_minutes] || 45

      # Step 1: Create routine first and get DB ID immediately
      routine = @user.workout_routines.create!(
        level: level,
        week_number: calculate_week_number,
        day_number: day_num,
        workout_type: workout_type,
        day_of_week: day_str,
        estimated_duration: duration,
        generated_at: Time.current
      )

      # Set DB ID immediately after routine creation
      Rails.logger.info("[RoutineService] Created routine with DB ID: #{routine.id} (AI ID was: #{result[:routine_id]})")
      result[:routine_id] = routine.id.to_s
      result[:db_routine] = routine

      # Step 2: Add exercises (errors here won't lose the routine_id)
      exercises = result[:exercises] || []
      Rails.logger.info("[RoutineService] Adding #{exercises.length} exercises to routine #{routine.id}")

      Rails.logger.info("[RoutineService] Exercise names from AI: #{exercises.map { |e| e[:exercise_name] }.join(', ')}")

      exercises.each_with_index do |ex, idx|
        begin
          Rails.logger.info("[RoutineService] Adding exercise #{idx + 1}: #{ex[:exercise_name]}")

          routine.routine_exercises.create!(
            exercise_name: ex[:exercise_name] || "Unknown Exercise",
            order_index: ex[:order] || idx,
            sets: ex[:sets] || 3,
            reps: ex[:reps],
            target_muscle: ex[:target_muscle] || "other",
            rest_duration_seconds: ex[:rest_seconds] || default_rest_seconds,
            how_to: ex[:instructions],
            weight_description: ex[:weight_description] || ex[:weight_guide]
          )
        rescue StandardError => ex_error
          Rails.logger.error("[RoutineService] Failed to add exercise '#{ex[:exercise_name]}': #{ex_error.message}")
          Rails.logger.error("[RoutineService] Exercise data: #{ex.inspect}")
          # Continue with other exercises
        end
      end

      Rails.logger.info("[RoutineService] Finished adding exercises. Total in DB: #{routine.routine_exercises.reload.count}")

      result
    rescue StandardError => e
      Rails.logger.error("[RoutineService] Failed to create routine: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      # Return result with original AI ID if routine creation fails completely
      result
    end

    def default_rest_seconds
      level = @user.user_profile&.numeric_level || 1
      case level
      when 1..2 then 90   # beginner: longer rest
      when 3..5 then 75   # intermediate
      else 60              # advanced: shorter rest
      end
    end

    def calculate_week_number
      start_date = @user.user_profile&.onboarding_completed_at || @user.created_at
      ((Time.current - start_date) / 1.week).floor + 1
    end

    def day_name(day)
      %w[sunday monday tuesday wednesday thursday friday saturday][day.to_i]
    end

    def day_index(day_str)
      %w[sunday monday tuesday wednesday thursday friday saturday].index(day_str.to_s.downcase) || 0
    end
  end
end
