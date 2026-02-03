# frozen_string_literal: true

module Queries
  class MyTrainingProgram < BaseQuery
    description "Get the current user's active training program"

    type Types::TrainingProgramType, null: true

    def resolve
      authenticate_user!

      current_user.active_training_program
    end
  end
end
