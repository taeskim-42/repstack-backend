# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    # Authentication
    field :sign_in_with_apple, mutation: Mutations::SignInWithApple
    field :dev_sign_in, mutation: Mutations::DevSignIn

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

    # AI Trainer
    field :check_condition, mutation: Mutations::CheckCondition
    field :check_condition_from_voice, mutation: Mutations::CheckConditionFromVoice
    field :record_workout, mutation: Mutations::RecordWorkout
    field :submit_feedback, mutation: Mutations::SubmitFeedback
    field :submit_feedback_from_voice, mutation: Mutations::SubmitFeedbackFromVoice

    # AI Trainer - Routine & Level Test
    field :generate_ai_routine, mutation: Mutations::GenerateAiRoutine
    field :start_level_test, mutation: Mutations::StartLevelTest
    field :submit_level_test_result, mutation: Mutations::SubmitLevelTestResult
  end
end
