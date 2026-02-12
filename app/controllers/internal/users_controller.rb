# frozen_string_literal: true

module Internal
  class UsersController < BaseController
    skip_before_action :set_user
    before_action :set_user_from_path

    # GET /internal/users/:id/profile
    def profile
      p = @user.user_profile

      render_success(
        user: {
          id: @user.id,
          name: @user.name,
          email: @user.email
        },
        profile: p ? {
          numeric_level: p.numeric_level,
          current_level: p.current_level,
          fitness_goal: p.fitness_goal,
          height: p.height,
          weight: p.weight,
          body_fat_percentage: p.body_fat_percentage,
          total_workouts_completed: p.total_workouts_completed,
          onboarding_completed: p.onboarding_completed_at.present?,
          injuries: p.fitness_factors&.dig("collected_data", "injuries"),
          frequency: p.fitness_factors&.dig("collected_data", "frequency"),
          environment: p.fitness_factors&.dig("collected_data", "environment")
        } : nil
      )
    end

    # GET /internal/users/:id/history
    def history
      days = (params[:days] || 7).to_i.clamp(1, 90)
      since = days.days.ago.beginning_of_day

      sessions = @user.workout_sessions
                      .where("start_time >= ?", since)
                      .where.not(end_time: nil)
                      .order(start_time: :desc)
                      .limit(30)

      routines = @user.workout_routines
                      .where("created_at >= ?", since)
                      .includes(:routine_exercises)
                      .order(created_at: :desc)
                      .limit(30)

      render_success(
        sessions: sessions.map { |s|
          {
            id: s.id,
            name: s.name,
            start_time: s.start_time,
            end_time: s.end_time,
            total_sets: s.total_sets,
            total_volume: s.total_volume,
            exercises_performed: s.exercises_performed
          }
        },
        routines: routines.map { |r|
          {
            id: r.id,
            day_of_week: r.day_of_week,
            workout_type: r.workout_type,
            is_completed: r.is_completed,
            created_at: r.created_at,
            exercise_count: r.routine_exercises.size
          }
        },
        summary: {
          total_sessions: sessions.size,
          total_routines: routines.size,
          completed_routines: routines.count(&:is_completed)
        }
      )
    end

    # GET /internal/users/:id/today_routine
    def today_routine
      today_dow = Time.current.wday == 0 ? 7 : Time.current.wday

      routine = WorkoutRoutine.where(user_id: @user.id)
                              .where("created_at >= ?", Time.current.beginning_of_day)
                              .where(day_number: today_dow)
                              .where(is_completed: false)
                              .includes(:routine_exercises)
                              .order(created_at: :desc)
                              .first

      # Check baseline if no today routine
      unless routine
        program = @user.active_training_program
        if program
          routine = program.workout_routines
                           .where(week_number: program.current_week, day_number: today_dow)
                           .where(is_completed: false)
                           .includes(:routine_exercises)
                           .order(created_at: :desc)
                           .first
          routine = nil unless routine&.routine_exercises&.any?
        end
      end

      if routine
        render_success(
          exists: true,
          routine: format_routine(routine)
        )
      else
        render_success(exists: false, routine: nil)
      end
    end

    # GET /internal/users/:id/memory
    def memory
      context = ConversationMemoryService.format_context(@user)
      factors = @user.user_profile&.fitness_factors || {}

      render_success(
        formatted_context: context,
        key_facts: factors["trainer_memories"] || [],
        session_summaries: factors["session_summaries"] || [],
        personality_profile: factors["personality_profile"],
        progress_timeline: factors["progress_timeline"] || []
      )
    end

    # POST /internal/users/:id/memory
    def write_memory
      profile = @user.user_profile
      return render_error("프로필이 없습니다.") unless profile

      factors = profile.fitness_factors || {}

      # Write key fact
      if params[:fact].present?
        memories = factors["trainer_memories"] || []
        memories << {
          "fact" => params[:fact],
          "category" => params[:category] || "personal",
          "date" => Time.current.strftime("%Y-%m-%d")
        }
        # Deduplicate
        memories = memories.uniq { |f| f["fact"].to_s.gsub(/\s+/, "").downcase }
        factors["trainer_memories"] = memories.last(50)
      end

      # Write personality profile
      if params[:personality_profile].present?
        factors["personality_profile"] = params[:personality_profile]
      end

      # Write progress milestone
      if params[:milestone].present?
        timeline = factors["progress_timeline"] || []
        timeline << {
          "event" => params[:milestone],
          "date" => Time.current.strftime("%Y-%m-%d"),
          "type" => params[:milestone_type] || "general"
        }
        factors["progress_timeline"] = timeline.last(50)
      end

      profile.update!(fitness_factors: factors)
      render_success(updated: true)
    end

    private

    def set_user_from_path
      @user = User.find_by(id: params[:id])
      render json: { error: "User not found" }, status: :not_found unless @user
    end

    def format_routine(routine)
      day_names = %w[일요일 월요일 화요일 수요일 목요일 금요일 토요일]
      day_index = routine.day_number || 1

      {
        id: routine.id,
        routine_id: routine.id.to_s,
        day_of_week: routine.day_of_week || routine.day_number.to_s,
        day_korean: day_names[day_index] || "월요일",
        day_number: routine.day_number,
        week_number: routine.week_number,
        tier: routine.level || "beginner",
        user_level: @user.user_profile&.numeric_level || 1,
        fitness_factor: routine.workout_type || "strength",
        fitness_factor_korean: routine.workout_type || "근력",
        estimated_duration: routine.estimated_duration,
        estimated_duration_minutes: routine.estimated_duration || 45,
        generated_at: routine.created_at&.iso8601 || Time.current.iso8601,
        workout_type: routine.workout_type,
        is_completed: routine.is_completed,
        exercises: routine.routine_exercises.order(:order_index).map do |ex|
          {
            exercise_id: ex.id.to_s,
            exercise_name: ex.exercise_name,
            order: ex.order_index + 1,
            sets: ex.sets,
            reps: ex.reps,
            target_weight_kg: ex.weight&.to_f,
            weight_description: ex.weight_description,
            target_muscle: ex.target_muscle || "전신",
            rest_seconds: ex.rest_duration_seconds,
            instructions: ex.how_to,
            bpm: ex.bpm,
            range_of_motion: ex.range_of_motion,
            order_index: ex.order_index
          }
        end
      }
    end
  end
end
