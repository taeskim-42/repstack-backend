# frozen_string_literal: true

module Types
  class SavedRoutineType < Types::BaseObject
    description "A routine saved to the calendar"

    field :id, ID, null: false
    field :day_of_week, Integer, null: false
    field :week_start_date, String, null: false
    field :routine, Types::WorkoutRoutineType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
