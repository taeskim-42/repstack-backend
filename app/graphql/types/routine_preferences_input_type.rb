# frozen_string_literal: true

module Types
  class RoutinePreferencesInputType < Types::BaseInputObject
    description "Preferences for dynamic routine generation"

    argument :split_type, String, required: false,
             description: "Split type: full_body, upper_lower, push_pull_legs, four_day, five_day, fitness_factor_based"

    argument :available_equipment, [String], required: false,
             description: "Available equipment: none, shark_rack, dumbbell, barbell, cable, machine, pull_up_bar, bench"

    argument :workout_duration_minutes, Integer, required: false,
             description: "Target workout duration in minutes"

    argument :preferred_training_methods, [String], required: false,
             description: "Preferred methods: standard, bpm, tabata, dropset, superset, fill_target"

    argument :avoid_exercises, [String], required: false,
             description: "Exercise english names to avoid"

    argument :focus_muscles, [String], required: false,
             description: "Muscle groups to prioritize: chest, back, legs, shoulders, arms, core"
  end
end
