# frozen_string_literal: true

module Mutations
  class VerifySubscription < BaseMutation
    description "Verify current subscription status and tier"

    field :success, Boolean, null: false
    field :is_premium, Boolean, null: false, description: "True if user has any paid subscription (pro or max)"
    field :tier, String, null: false, description: "Current tier: free, pro, or max"
    field :subscription, Types::SubscriptionType, null: true
    field :error, String, null: true

    def resolve
      authenticate_user!

      subscription = current_user.active_subscription

      {
        success: true,
        is_premium: current_user.premium?,
        tier: current_user.subscription_tier.to_s,
        subscription: subscription,
        error: nil
      }
    rescue StandardError => e
      Rails.logger.error("VerifySubscription error: #{e.message}")
      { success: false, is_premium: false, tier: "free", subscription: nil, error: "구독 상태 확인에 실패했습니다." }
    end
  end
end
