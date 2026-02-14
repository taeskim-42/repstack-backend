# frozen_string_literal: true

module Types
  class UsageStatusType < Types::BaseObject
    field :tier, String, null: false, description: "Current subscription tier: free, pro, or max"
    field :routine_limits, [Types::UsageLimitType], null: false, description: "Routine-related limits"
    field :usage_limits, [Types::UsageLimitType], null: false, description: "Chat and agent limits"
    field :features, GraphQL::Types::JSON, null: false, description: "Feature access levels"
  end
end
