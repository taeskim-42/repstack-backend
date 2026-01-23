# frozen_string_literal: true

module Types
  class LevelTestResultsType < Types::BaseObject
    description "Results of a level test evaluation"

    field :passed_exercises, [ Types::ExerciseResultType ], null: false
    field :failed_exercises, [ Types::ExerciseResultType ], null: false
    field :total_exercises, Integer, null: false
    field :pass_rate, Float, null: false
  end
end
