# frozen_string_literal: true

# Delete all user-related data in FK-safe order.
# Used by both admin delete_user_data and DeleteAccount mutation.
class UserDataDeleter
  # Delete all dependent data for user. Does NOT delete the user record itself.
  def self.delete_all_for(user)
    counts = {}
    uid = user.id

    # Leaf tables first (no dependents)
    counts[:onboarding_analytics] = safe_delete { OnboardingAnalytics.where(user_id: uid).delete_all }
    counts[:chat_messages] = safe_delete { ChatMessage.where(user_id: uid).delete_all }
    counts[:condition_logs] = safe_delete { ConditionLog.where(user_id: uid).delete_all }
    counts[:workout_feedbacks] = safe_delete { WorkoutFeedback.where(user_id: uid).delete_all }
    counts[:level_test_verifications] = safe_delete { LevelTestVerification.where(user_id: uid).delete_all }
    counts[:subscriptions] = safe_delete { Subscription.where(user_id: uid).delete_all }

    # fitness_test_submissions (table may exist in DB even if model is absent)
    counts[:fitness_test_submissions] = safe_delete do
      ActiveRecord::Base.connection.execute(
        "DELETE FROM fitness_test_submissions WHERE user_id = #{uid.to_i}"
      ).cmd_tuples
    end

    # agent_conversation_messages → agent_sessions (child first)
    counts[:agent_conversation_messages] = safe_delete do
      agent_ids = AgentSession.where(user_id: uid).pluck(:id)
      agent_ids.any? ? AgentConversationMessage.where(agent_session_id: agent_ids).delete_all : 0
    end
    counts[:agent_sessions] = safe_delete { AgentSession.where(user_id: uid).delete_all }

    # workout_records references workout_sessions
    counts[:workout_records] = safe_delete { WorkoutRecord.where(user_id: uid).delete_all }

    # workout_sets → workout_sessions
    counts[:workout_sets] = safe_delete do
      WorkoutSet.joins(:workout_session).where(workout_sessions: { user_id: uid }).delete_all
    end
    counts[:workout_sessions] = safe_delete { WorkoutSession.where(user_id: uid).delete_all }

    # routine_exercises → workout_routines
    counts[:routine_exercises] = safe_delete do
      RoutineExercise.joins(:workout_routine).where(workout_routines: { user_id: uid }).delete_all
    end
    counts[:workout_routines] = safe_delete { WorkoutRoutine.where(user_id: uid).delete_all }

    counts[:training_programs] = safe_delete { TrainingProgram.where(user_id: uid).delete_all }
    counts[:user_profile] = safe_delete { UserProfile.where(user_id: uid).delete_all }

    Rails.logger.info("[UserDataDeleter] Deleted for user #{uid}: #{counts}")
    counts
  end

  # Safely execute deletion, returning 0 if table doesn't exist or other DB error
  def self.safe_delete
    yield
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("[UserDataDeleter] Skipped (table may not exist): #{e.message}")
    0
  rescue StandardError => e
    Rails.logger.warn("[UserDataDeleter] Error: #{e.message}")
    0
  end

  private_class_method :safe_delete
end
