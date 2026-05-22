# frozen_string_literal: true

require_relative "constants"
require_relative "tool_based_routine_generator"

module AiTrainer
  # Wrapper service for routine generation.
  #
  # Single path: ToolBasedRoutineGenerator. The legacy CreativeRoutineGenerator
  # branch (gated by USE_TOOL_BASED_GENERATOR) and the rescue fallback to it
  # were removed (R13 consensus, D12) — feature flag was always true in prod
  # so the Creative path was effectively dead while still confusing reads.
  #
  # `recent_feedbacks` preferences are now merged into the condition text
  # instead of being passed to a separate `with_preferences` builder.
  class RoutineService
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
      merged_condition = merge_feedback_preferences(condition, recent_feedbacks)
      result = generate_with_tool_based(day_of_week, merged_condition, goal)

      return nil unless result.is_a?(Hash)

      # Rest day: return directly without saving
      return result if result[:rest_day]

      return nil unless result[:routine_id]

      save_routine_to_db(result)

      result
    end

    private

    def generate_with_tool_based(day_of_week, condition, goal)
      generator = ToolBasedRoutineGenerator.new(user: @user, day_of_week: day_of_week)

      generator.with_goal(goal) if goal.present?
      generator.with_condition(condition) if condition.present?

      generator.generate
    end

    # Merge recent_feedbacks-derived preferences into the condition payload so
    # ToolBased sees them in the prompt (R13: preserve Creative's prefs
    # semantics by promoting them to free-text notes).
    def merge_feedback_preferences(condition, feedbacks)
      return condition if feedbacks.blank?

      prefs_note = build_preferences_note(feedbacks)
      return condition if prefs_note.blank?

      case condition
      when nil
        { notes: prefs_note }
      when String
        "#{condition}\n#{prefs_note}".strip
      when Hash
        merged = condition.dup
        existing = merged[:notes].presence || merged["notes"].presence
        merged[:notes] = [ existing, prefs_note ].compact.join("\n").strip
        merged
      else
        condition
      end
    end

    def build_preferences_note(feedbacks)
      avoid = []
      preferred = []
      intensity = nil

      feedbacks.each do |fb|
        case fb.feedback_type
        when "too_hard", "injury_risk"
          avoid << fb.exercise_name if fb.exercise_name
          intensity = "lower"
        when "too_easy"
          intensity = "higher"
        when "enjoyed"
          preferred << fb.exercise_name if fb.exercise_name
        end
      end

      parts = []
      parts << "최근 피드백 기반 회피 운동: #{avoid.uniq.join(', ')}" if avoid.any?
      parts << "선호 운동: #{preferred.uniq.join(', ')}" if preferred.any?
      parts << "강도 조정: #{intensity}" if intensity
      parts.join(" / ").presence
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

      # Check for active program and replace baseline routine if exists
      program = @user.active_training_program
      week_num = calculate_week_number

      if program
        existing_baseline = program.workout_routines.find_by(
          week_number: week_num,
          day_number: day_num,
          generation_source: "program_baseline"
        )
        if existing_baseline
          Rails.logger.info("[RoutineService] Replacing baseline routine #{existing_baseline.id} with condition-adjusted")
          existing_baseline.destroy!
        end
      end

      # Step 1: Create routine first and get DB ID immediately
      routine = @user.workout_routines.create!(
        training_program_id: program&.id,
        generation_source: program ? "condition_adjusted" : "ai",
        level: level,
        week_number: week_num,
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
            exercise_name_english: ex[:exercise_name_english],
            order_index: ex[:order] || idx,
            sets: ex[:sets] || 3,
            reps: parse_reps(ex[:reps]),
            target_muscle: ex[:target_muscle] || "other",
            target_muscle_korean: ex[:target_muscle_korean],
            rest_duration_seconds: ex[:rest_seconds] || default_rest_seconds,
            how_to: ex[:instructions],
            weight: ex[:target_weight_kg],
            weight_description: ex[:weight_description],
            weight_guide: ex[:weight_guide],
            range_of_motion: ex[:rom],
            rpe: ex[:rpe],
            tempo: ex[:tempo],
            bpm: ex[:bpm],
            work_seconds: ex[:work_seconds],
            equipment: ex[:equipment],
            source_program: ex[:source_program],
            expert_tips: ex[:expert_tips] || [],
            form_cues: ex[:form_cues] || []
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

    # Parse reps from LLM output: "10" → 10, "10-12" → 10, 10 → 10
    def parse_reps(value)
      return nil if value.nil?
      return value if value.is_a?(Integer) && value.positive?

      str = value.to_s.strip
      if str =~ /(\d+)/
        num = ::Regexp.last_match(1).to_i
        num.positive? ? num : nil
      end
    end

    def day_name(day)
      %w[sunday monday tuesday wednesday thursday friday saturday][day.to_i]
    end

    def day_index(day_str)
      %w[sunday monday tuesday wednesday thursday friday saturday].index(day_str.to_s.downcase) || 0
    end
  end
end
