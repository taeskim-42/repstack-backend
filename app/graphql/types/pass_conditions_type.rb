# frozen_string_literal: true

module Types
  class PassConditionsType < Types::BaseObject
    description "Conditions required to pass the level test"

    field :all_exercises_required, Boolean, null: false
    field :minimum_exercises, Integer, null: false
    field :exercises, [Types::PassConditionExerciseType], null: false
  end
end
