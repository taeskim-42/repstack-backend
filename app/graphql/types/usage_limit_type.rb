# frozen_string_literal: true

module Types
  class UsageLimitType < Types::BaseObject
    field :action, String, null: false, description: "Action name (e.g., routine_generation, ai_chat)"
    field :limit, Integer, null: false, description: "Maximum allowed per period"
    field :used, Integer, null: false, description: "Amount used in current period"
    field :remaining, Integer, null: false, description: "Remaining in current period"
    field :period, String, null: false, description: "Reset period: daily or weekly"
  end
end
