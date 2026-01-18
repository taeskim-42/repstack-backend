# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    # Authentication
    field :sign_up, mutation: Mutations::SignUp
    field :sign_in, mutation: Mutations::SignIn
    
    # User Profile
    field :update_profile, mutation: Mutations::UpdateProfile
    field :update_user_profile, mutation: Mutations::UpdateUserProfile
    
    # Workout Sessions
    field :create_workout_session, mutation: Mutations::CreateWorkoutSession
    field :start_workout_session, mutation: Mutations::StartWorkoutSession
    field :end_workout_session, mutation: Mutations::EndWorkoutSession
    field :log_workout_set, mutation: Mutations::LogWorkoutSet
    field :add_workout_set, mutation: Mutations::AddWorkoutSet
    
    # Routines
    field :save_routine, mutation: Mutations::SaveRoutine
    field :generate_routine, mutation: Mutations::GenerateRoutine
    field :complete_routine, mutation: Mutations::CompleteRoutine
  end
end