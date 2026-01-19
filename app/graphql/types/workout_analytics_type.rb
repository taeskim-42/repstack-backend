# frozen_string_literal: true

module Types
  class WorkoutAnalyticsType < Types::BaseObject
    description "Workout analytics and statistics"

    field :total_workouts, Integer, null: false, description: "Total number of workouts"
    field :total_time, Integer, null: false, description: "Total workout time in minutes"
    field :average_rpe, Float, null: false, description: "Average rate of perceived exertion"
    field :completion_rate, Float, null: false, description: "Workout completion rate 0-1"
    field :workout_frequency, Float, null: false, description: "Workouts per week"
    field :muscle_group_distribution, GraphQL::Types::JSON, null: false, description: "Distribution by muscle group"
    field :progression_trends, GraphQL::Types::JSON, null: false, description: "Progression trends by exercise"
  end
end
