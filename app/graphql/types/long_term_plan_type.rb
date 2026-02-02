# frozen_string_literal: true

module Types
  # Define WeeklyScheduleDayType first since LongTermPlanType references it
  class WeeklyScheduleDayType < Types::BaseObject
    description "Single day in the weekly schedule"

    field :day, Integer, null: false, description: "Day number (1=Monday, 7=Sunday)"
    field :focus, String, null: false, description: "Focus area for this day"
    field :muscles, [String], null: true, description: "Target muscle groups"
  end

  class LongTermPlanType < Types::BaseObject
    description "Long-term workout plan based on user's goals and level"

    field :tier, String, null: true, description: "User's tier (beginner/intermediate/advanced)"
    field :goal, String, null: true, description: "User's fitness goal"
    field :days_per_week, Integer, null: true, description: "Recommended training days per week"
    field :weekly_split, String, null: true, description: "Weekly split description (e.g., '전신 운동 (주 3회)')"
    field :weekly_schedule, [Types::WeeklyScheduleDayType], null: true, description: "Detailed weekly schedule"
    field :description, String, null: true, description: "Training strategy description"
    field :progression_strategy, String, null: true, description: "Progressive overload strategy"
    field :estimated_timeline, String, null: true, description: "Estimated timeline to see results"
  end
end
