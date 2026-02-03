# frozen_string_literal: true

module Types
  class SplitDayType < Types::BaseObject
    description "Split schedule for a specific day"

    field :day_number, Int, null: false, description: "Day of week (1=Monday, 7=Sunday)"
    field :focus, String, null: false, description: "Focus for this day (e.g., '상체', '하체', '휴식')"
    field :muscles, [String], null: false, description: "Target muscle groups"
  end
end
