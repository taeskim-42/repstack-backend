# frozen_string_literal: true

module Types
  class ExerciseResultType < Types::BaseObject
    description "Result for a single exercise in the test"

    field :exercise, String, null: false
    field :required, Float, null: false
    field :achieved, Float, null: false
    field :status, String, null: false
    field :gap, Float, null: true, description: "Weight gap if failed"
  end
end
