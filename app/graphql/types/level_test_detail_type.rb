# frozen_string_literal: true

module Types
  class LevelTestDetailType < Types::BaseObject
    description "Details of a level-up test (승급 시험)"

    field :test_id, String, null: false
    field :current_level, Integer, null: false
    field :target_level, Integer, null: false
    field :test_type, String, null: false
    field :criteria, Types::LevelTestCriteriaType, null: false
    field :exercises, [ Types::LevelTestExerciseType ], null: false
    field :instructions, [ String ], null: false
    field :time_limit_minutes, Integer, null: false
    field :pass_conditions, Types::PassConditionsType, null: false
  end
end
