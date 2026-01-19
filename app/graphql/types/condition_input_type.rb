# frozen_string_literal: true

module Types
  class ConditionInputType < Types::BaseInputObject
    description "Input for daily condition check"

    argument :energy_level, Integer, required: true,
      description: "Energy level 1-5 scale"
    argument :stress_level, Integer, required: true,
      description: "Stress level 1-5 scale"
    argument :sleep_quality, Integer, required: true,
      description: "Sleep quality 1-5 scale"
    argument :soreness, GraphQL::Types::JSON, required: false,
      description: "Muscle soreness map (muscle_group => level 1-5)"
    argument :motivation, Integer, required: true,
      description: "Motivation level 1-5 scale"
    argument :available_time, Integer, required: true,
      description: "Available time in minutes"
    argument :notes, String, required: false,
      description: "Additional notes"
  end
end
