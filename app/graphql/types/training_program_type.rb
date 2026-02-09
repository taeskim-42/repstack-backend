# frozen_string_literal: true

module Types
  class TrainingProgramType < Types::BaseObject
    description "Long-term training program framework generated via RAG + LLM"

    field :id, ID, null: false
    field :name, String, null: false, description: "Program name"
    field :status, String, null: false, description: "Program status (active, completed, paused)"
    field :goal, String, null: true, description: "Training goal"
    field :total_weeks, Int, null: true, description: "Total program duration in weeks"
    field :current_week, Int, null: false, description: "Current week number"
    field :periodization_type, String, null: true, description: "Periodization type (linear, undulating, block)"
    field :started_at, GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    # Computed fields
    field :progress_percentage, Int, null: false, description: "Progress percentage (0-100)"
    field :current_phase, String, null: true, description: "Current phase name"
    field :current_theme, String, null: true, description: "Current phase theme"
    field :current_volume_modifier, Float, null: false, description: "Current volume adjustment multiplier"
    field :is_deload_week, Boolean, null: false, description: "Whether current week is a deload week"

    # Structured data
    field :weekly_phases, [Types::WeeklyPhaseType], null: false, description: "Weekly plan phases"
    field :split_schedule, [Types::SplitDayType], null: false, description: "Weekly split schedule"

    # Workout sessions within this program
    field :workout_sessions, [Types::WorkoutSessionType], null: false, description: "Workout sessions during this program" do
      argument :week, Int, required: false, description: "Filter by week number (1-based)"
    end

    # Pre-generated routines
    field :week_routines, [Types::WorkoutRoutineType], null: false,
          description: "Pre-generated routines for a specific week" do
      argument :week, Int, required: true, description: "Week number (1-based)"
    end
    field :routines_generated, Boolean, null: false,
          description: "Whether baseline routines have been generated"

    # Today's info
    field :today_focus, String, null: true, description: "Today's training focus"
    field :today_muscles, [String], null: false, description: "Today's target muscles"

    def progress_percentage
      object.progress_percentage
    end

    def current_phase
      object.current_phase
    end

    def current_theme
      object.current_theme
    end

    def current_volume_modifier
      object.current_volume_modifier
    end

    def is_deload_week
      object.deload_week?
    end

    def weekly_phases
      return [] if object.weekly_plan.blank?

      object.weekly_plan.map do |week_range, info|
        {
          week_range: week_range.to_s,
          phase: info["phase"] || info[:phase] || "",
          theme: info["theme"] || info[:theme],
          volume_modifier: (info["volume_modifier"] || info[:volume_modifier] || 1.0).to_f,
          focus: info["focus"] || info[:focus]
        }
      end
    end

    def split_schedule
      return [] if object.split_schedule.blank?

      object.split_schedule.map do |day_num, info|
        {
          day_number: day_num.to_i,
          focus: info["focus"] || info[:focus] || "휴식",
          muscles: info["muscles"] || info[:muscles] || []
        }
      end.sort_by { |d| d[:day_number] }
    end

    def workout_sessions(week: nil)
      sessions = object.user.workout_sessions.includes(:workout_sets)

      if week && object.started_at
        week_start = object.started_at.to_date + ((week - 1) * 7).days
        week_end = week_start + 7.days
        sessions = sessions.where(start_time: week_start.beginning_of_day..week_end.beginning_of_day)
      elsif object.started_at
        sessions = sessions.where("start_time >= ?", object.started_at)
      end

      sessions.order(start_time: :desc)
    end

    def week_routines(week:)
      object.routines_for_week(week)
    end

    def routines_generated
      object.routines_generated?
    end

    def today_focus
      today = object.today_focus
      today&.dig("focus") || today&.dig(:focus)
    end

    def today_muscles
      today = object.today_focus
      today&.dig("muscles") || today&.dig(:muscles) || []
    end
  end
end
