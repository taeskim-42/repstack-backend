# frozen_string_literal: true

module Types
  class LevelTestVerificationInputType < Types::BaseInputObject
    description "Input for submitting level test verification"

    argument :test_id, String, required: false,
             description: "Test ID (auto-generated if not provided)"
    argument :exercises, [Types::ExerciseVerificationInputType], required: true,
             description: "List of exercise verifications"
    argument :device_info, GraphQL::Types::JSON, required: false,
             description: "Device and CoreML version info"
  end
end
