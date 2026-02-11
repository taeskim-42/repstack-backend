# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    # Authentication
    field :sign_in_with_apple, mutation: Mutations::SignInWithApple
    if Rails.env.development? || Rails.env.test?
      field :dev_sign_in, mutation: Mutations::DevSignIn
      field :dev_sign_in_fresh, mutation: Mutations::DevSignInFresh
    end

    # User Profile
    field :update_profile, mutation: Mutations::UpdateProfile
    field :update_user_profile, mutation: Mutations::UpdateUserProfile

    # Workout Sessions
    field :start_workout_session, mutation: Mutations::StartWorkoutSession
    field :end_workout_session, mutation: Mutations::EndWorkoutSession
    field :add_workout_set, mutation: Mutations::AddWorkoutSet

    # Routines
    field :save_routine, mutation: Mutations::SaveRoutine
    field :complete_routine, mutation: Mutations::CompleteRoutine
    field :delete_routine, mutation: Mutations::DeleteRoutine

    # AI Trainer
    field :chat, mutation: Mutations::Chat
    field :check_condition, mutation: Mutations::CheckCondition
    field :check_condition_from_voice, mutation: Mutations::CheckConditionFromVoice
    field :record_workout, mutation: Mutations::RecordWorkout
    field :submit_feedback, mutation: Mutations::SubmitFeedback
    field :submit_feedback_from_voice, mutation: Mutations::SubmitFeedbackFromVoice

    # AI Trainer - Routine & Level Test
    field :generate_ai_routine, mutation: Mutations::GenerateAiRoutine
    field :start_level_test, mutation: Mutations::StartLevelTest
    field :submit_level_test_result, mutation: Mutations::SubmitLevelTestResult
    field :submit_level_test_verification, mutation: Mutations::SubmitLevelTestVerification

    # Offline sync
    field :sync_offline_records, mutation: Mutations::SyncOfflineRecords

    # Routine management
    field :add_exercise_to_routine, mutation: Mutations::AddExerciseToRoutine
    field :save_routine_to_calendar, mutation: Mutations::SaveRoutineToCalendar
    field :replace_exercise, mutation: Mutations::ReplaceExercise
    field :regenerate_routine, mutation: Mutations::RegenerateRoutine

    # Account management
    field :delete_account, mutation: Mutations::DeleteAccount

    # Test utilities (development only)
    if Rails.env.development? || Rails.env.test?
      field :create_test_user, mutation: Mutations::CreateTestUser
    end
  end
end
