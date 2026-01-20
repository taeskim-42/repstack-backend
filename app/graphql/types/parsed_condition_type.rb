# frozen_string_literal: true

module Types
  class ParsedConditionType < Types::BaseObject
    description "Parsed condition data from voice input"

    field :energy_level, Integer, null: false, description: "Energy level 1-5"
    field :stress_level, Integer, null: false, description: "Stress level 1-5"
    field :sleep_quality, Integer, null: false, description: "Sleep quality 1-5"
    field :motivation, Integer, null: false, description: "Motivation level 1-5"
    field :soreness, GraphQL::Types::JSON, null: true, description: "Muscle soreness map"
    field :available_time, Integer, null: false, description: "Available time in minutes"
    field :notes, String, null: true, description: "Additional notes"
  end
end
