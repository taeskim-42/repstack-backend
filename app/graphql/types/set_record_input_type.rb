# frozen_string_literal: true

module Types
  class SetRecordInputType < Types::BaseInputObject
    description "Input for recording a single set"

    argument :set_number, Integer, required: true,
      description: "Set number (1-indexed)"
    argument :reps, Integer, required: true,
      description: "Number of reps completed"
    argument :weight, Float, required: false,
      description: "Weight used in kg"
    argument :duration, Integer, required: false,
      description: "Duration in seconds for timed exercises"
    argument :rest_after_set, Integer, required: false,
      description: "Rest time after this set in seconds"
    argument :rpe, Integer, required: false,
      description: "Rate of Perceived Exertion 1-10"
    argument :notes, String, required: false,
      description: "Notes for this set"
  end
end
