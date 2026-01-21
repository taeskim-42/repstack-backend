# frozen_string_literal: true

module Types
  class AddExerciseToRoutineInputType < Types::BaseInputObject
    graphql_name "AddExerciseRoutineInput"
    description "Input for adding an exercise to a routine"

    argument :routine_id, ID, required: true, description: "Target routine ID"
    argument :exercise_id, String, required: false, description: "Exercise ID from catalog (e.g., EX_CH01)"
    argument :exercise_name, String, required: false, description: "Custom exercise name"
    argument :sets, Integer, required: false, default_value: 3, description: "Number of sets"
    argument :reps, Integer, required: false, default_value: 10, description: "Number of reps"
    argument :weight, Float, required: false, description: "Weight in kg"
    argument :target_muscle, String, required: false, description: "Target muscle group"
    argument :order_index, Integer, required: false, description: "Order position (defaults to last)"

    def prepare
      unless exercise_id.present? || exercise_name.present?
        raise GraphQL::ExecutionError, "exercise_id 또는 exercise_name 중 하나는 필수입니다"
      end

      super
    end
  end
end
