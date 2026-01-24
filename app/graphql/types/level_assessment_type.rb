# frozen_string_literal: true

module Types
  class LevelAssessmentType < Types::BaseObject
    description "User level assessment result from onboarding conversation"

    field :experience_level, String, null: true, description: "Experience level (beginner, intermediate, advanced)"
    field :numeric_level, Int, null: true, description: "Numeric level (1-8) - set after fitness test"
    field :fitness_goal, String, null: true, description: "Primary fitness goal"
    field :summary, String, null: true, description: "Assessment summary"
  end
end
