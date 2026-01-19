# frozen_string_literal: true

module Types
  class LevelTestCriteriaType < Types::BaseObject
    description "Criteria for passing the level test"

    field :bench_press_kg, Float, null: false
    field :squat_kg, Float, null: false
    field :deadlift_kg, Float, null: false
    field :description, String, null: true
  end
end
