# frozen_string_literal: true

module Types
  class BodyInfoInputType < Types::BaseInputObject
    argument :height, Float, required: false
    argument :weight, Float, required: false
    argument :body_fat, Float, required: false
    argument :max_lifts, GraphQL::Types::JSON, required: false, description: "Maximum lift records as key-value pairs"
    argument :recent_workouts, [ GraphQL::Types::JSON ], required: false, description: "Array of recent workout data"
  end
end
