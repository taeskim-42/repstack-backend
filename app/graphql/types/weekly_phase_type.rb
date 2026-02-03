# frozen_string_literal: true

module Types
  class WeeklyPhaseType < Types::BaseObject
    description "Weekly phase information within a training program"

    field :week_range, String, null: false, description: "Week range string (e.g., '1-3', '4-8')"
    field :phase, String, null: false, description: "Phase name (e.g., '적응기', '성장기')"
    field :theme, String, null: true, description: "Training theme for this phase"
    field :volume_modifier, Float, null: false, description: "Volume adjustment multiplier (e.g., 0.8 = 80%)"
    field :focus, String, null: true, description: "Focus area for this phase"
  end
end
