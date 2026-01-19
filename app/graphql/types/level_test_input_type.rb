# frozen_string_literal: true

module Types
  class LevelTestInputType < Types::BaseInputObject
    graphql_name "LevelAssessmentInput"
    description "Input for level assessment test"

    argument :experience_level, String, required: true,
      description: "Experience level (BEGINNER, INTERMEDIATE, ADVANCED)"
    argument :workout_frequency, Integer, required: true,
      description: "Number of workouts per week"
    argument :strength_level, String, required: true,
      description: "Current strength level (BEGINNER, INTERMEDIATE, ADVANCED)"
    argument :endurance_level, String, required: true,
      description: "Current endurance level (BEGINNER, INTERMEDIATE, ADVANCED)"
    argument :injury_history, [String], required: false,
      description: "List of past injuries"
    argument :fitness_goals, [String], required: true,
      description: "Fitness goals (MUSCLE_GAIN, STRENGTH, WEIGHT_LOSS, etc.)"
    argument :available_equipment, [String], required: false,
      description: "Available equipment (bodyweight, dumbbells, barbell, etc.)"
  end
end
