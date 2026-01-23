# frozen_string_literal: true

module Types
  class ExerciseRecordInputType < Types::BaseInputObject
    description "Input for recording exercise performance"

    argument :exercise_name, String, required: true,
      description: "Name of the exercise"
    argument :target_muscle, String, required: true,
      description: "Target muscle group (CHEST, BACK, LEGS, etc.)"
    argument :planned_sets, Integer, required: true,
      description: "Number of planned sets"
    argument :completed_sets, [ Types::SetRecordInputType ], required: true,
      description: "Array of completed sets"
    argument :rest_time_between_sets, [ Integer ], required: false,
      description: "Rest time between each set in seconds"
  end
end
