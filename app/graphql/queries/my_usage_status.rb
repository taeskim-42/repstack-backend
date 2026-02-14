# frozen_string_literal: true

module Queries
  class MyUsageStatus < BaseQuery
    description "Get current user's subscription tier and usage limits"

    type Types::UsageStatusType, null: false

    def resolve
      authenticate_user!

      tier = current_user.subscription_tier
      routine_status = RoutineRateLimiter.status(user: current_user)
      usage_status = UsageLimiter.status(user: current_user)

      routine_limits = routine_status.map do |action, data|
        {
          action: action.to_s,
          limit: data[:limit],
          used: data[:used],
          remaining: data[:remaining],
          period: data[:period].to_s
        }
      end

      usage_limits = usage_status[:metered].map do |action, data|
        {
          action: action.to_s,
          limit: data[:limit],
          used: data[:used],
          remaining: data[:remaining],
          period: data[:period].to_s
        }
      end

      {
        tier: tier.to_s,
        routine_limits: routine_limits,
        usage_limits: usage_limits,
        features: usage_status[:features].transform_keys(&:to_s).transform_values(&:to_s)
      }
    end
  end
end
