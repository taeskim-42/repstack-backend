# frozen_string_literal: true

module Types
  class SaveRoutineToCalendarInputType < Types::BaseInputObject
    graphql_name "SaveRoutineCalendarInput"
    description "Input for saving a routine to the calendar"

    argument :routine_id, String, required: false, description: "Original routine ID (for reference)"
    argument :day_of_week, Integer, required: true, description: "Day of week (1=Monday ~ 7=Sunday)"
    argument :week_offset, Integer, required: false, default_value: 0, description: "Week offset (0=this week, 1=next week)"
    argument :estimated_duration, Integer, required: false, description: "Estimated duration in minutes"
    argument :exercises, [Types::RoutineExerciseInputType], required: true, description: "Exercises in the routine"
  end
end
