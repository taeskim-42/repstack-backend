# frozen_string_literal: true

module Types
  class UserConditionLogType < Types::BaseObject
    description "User's daily condition log"

    field :id, ID, null: false, description: "Condition log ID"
    field :user_id, ID, null: false, description: "User ID"
    field :date, String, null: false, description: "Log date ISO 8601"
    field :energy_level, Integer, null: false, description: "Energy level 1-5"
    field :stress_level, Integer, null: false, description: "Stress level 1-5"
    field :sleep_quality, Integer, null: false, description: "Sleep quality 1-5"
    field :soreness, GraphQL::Types::JSON, null: true, description: "Muscle soreness map"
    field :motivation, Integer, null: false, description: "Motivation level 1-5"
    field :available_time, Integer, null: false, description: "Available time in minutes"
    field :notes, String, null: true, description: "Additional notes"
    field :created_at, String, null: false, description: "Created timestamp ISO 8601"
  end
end
