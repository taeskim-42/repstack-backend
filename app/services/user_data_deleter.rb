# frozen_string_literal: true

# Delete all user-related data in FK-safe order.
# Used by both admin delete_user_data and DeleteAccount mutation.
class UserDataDeleter
  # Delete all dependent data for user. Does NOT delete the user record itself.
  def self.delete_all_for(user)
    counts = {}
    uid = user.id

    # Leaf tables first (no dependents)
    counts[:onboarding_analytics] = OnboardingAnalytics.where(user_id: uid).delete_all
    counts[:chat_messages] = ChatMessage.where(user_id: uid).delete_all
    counts[:condition_logs] = ConditionLog.where(user_id: uid).delete_all
    counts[:workout_feedbacks] = WorkoutFeedback.where(user_id: uid).delete_all
    counts[:level_test_verifications] = LevelTestVerification.where(user_id: uid).delete_all
    counts[:subscriptions] = Subscription.where(user_id: uid).delete_all

    # fitness_test_submissions (table may exist in DB even if model is absent)
    counts[:fitness_test_submissions] = begin
      ActiveRecord::Base.connection.execute(
        "DELETE FROM fitness_test_submissions WHERE user_id = #{uid.to_i}"
      ).cmd_tuples
    rescue StandardError
      0
    end

    # agent_conversation_messages → agent_sessions (child first)
    agent_ids = AgentSession.where(user_id: uid).pluck(:id)
    if agent_ids.any?
      counts[:agent_conversation_messages] = AgentConversationMessage.where(agent_session_id: agent_ids).delete_all
    end
    counts[:agent_sessions] = AgentSession.where(user_id: uid).delete_all

    # workout_records references workout_sessions
    counts[:workout_records] = WorkoutRecord.where(user_id: uid).delete_all

    # workout_sets → workout_sessions
    counts[:workout_sets] = WorkoutSet.joins(:workout_session).where(workout_sessions: { user_id: uid }).delete_all
    counts[:workout_sessions] = WorkoutSession.where(user_id: uid).delete_all

    # routine_exercises → workout_routines
    counts[:routine_exercises] = RoutineExercise.joins(:workout_routine).where(workout_routines: { user_id: uid }).delete_all
    counts[:workout_routines] = WorkoutRoutine.where(user_id: uid).delete_all

    counts[:training_programs] = TrainingProgram.where(user_id: uid).delete_all
    counts[:user_profile] = UserProfile.where(user_id: uid).delete_all

    counts
  end
end
