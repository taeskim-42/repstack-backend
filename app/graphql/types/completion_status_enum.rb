# frozen_string_literal: true

module Types
  class CompletionStatusEnum < Types::BaseEnum
    description "Workout completion status"

    value "COMPLETED", "Workout fully completed"
    value "PARTIAL", "Workout partially completed"
    value "SKIPPED", "Workout was skipped"
  end
end
