# frozen_string_literal: true

module Types
  class OneRmValuesType < Types::BaseObject
    description "1RM values for the 3 big lifts"

    field :bench, Float, null: true, description: "Bench press 1RM (kg)"
    field :squat, Float, null: true, description: "Squat 1RM (kg)"
    field :deadlift, Float, null: true, description: "Deadlift 1RM (kg)"
  end
end
