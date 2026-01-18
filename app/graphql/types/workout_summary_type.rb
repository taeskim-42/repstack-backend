module Types
  class WorkoutSummaryType < Types::BaseObject
    field :level, String, null: false
    field :week, Integer, null: false
    field :day, Integer, null: false
    field :exercises, Integer, null: false
    field :muscle_groups, [String], null: false
    field :estimated_duration, String, null: true
  end
end