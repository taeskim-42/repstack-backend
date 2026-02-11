# frozen_string_literal: true

module Internal
  class WorkoutsController < BaseController
    # POST /internal/workouts/complete
    def complete
      today_routine = WorkoutRoutine.where(user_id: @user.id)
                                     .where("created_at > ?", Time.current.beginning_of_day)
                                     .order(created_at: :desc)
                                     .first

      # End active workout session
      active_session = @user.workout_sessions.where(end_time: nil).order(created_at: :desc).first
      session_stats = { completed_sets: 0, total_volume: 0, exercises_count: 0 }

      if active_session
        session_stats[:completed_sets] = active_session.total_sets
        session_stats[:total_volume] = active_session.total_volume
        session_stats[:exercises_count] = active_session.exercises_performed
        active_session.complete!
      end

      # Complete the routine
      today_routine&.complete! unless today_routine&.is_completed

      # Mark workout completed in profile
      profile = @user.user_profile
      if profile
        factors = profile.fitness_factors || {}
        factors["last_workout_completed_at"] = Time.current.iso8601
        profile.update!(fitness_factors: factors)
      end

      render_success(
        routine_id: today_routine&.id,
        **session_stats
      )
    end
  end
end
