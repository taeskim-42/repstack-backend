# frozen_string_literal: true

module Types
  class LevelTestVerificationType < Types::BaseObject
    description "Level test verification result"

    field :test_id, String, null: false
    field :status, String, null: false,
          description: "Status: pending, in_progress, passed, failed"
    field :current_level, Int, null: false
    field :target_level, Int, null: false
    field :passed, Boolean, null: false
    field :new_level, Int, null: true,
          description: "New level after verification (if passed)"
    field :ai_feedback, String, null: true,
          description: "AI-generated feedback message"
    field :exercises, [Types::ExerciseVerificationResultType], null: false,
          description: "Individual exercise results"
    field :started_at, GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at, GraphQL::Types::ISO8601DateTime, null: true

    def exercises
      object.exercises.map do |ex|
        OpenStruct.new(ex.transform_keys(&:to_sym))
      end
    end
  end
end
