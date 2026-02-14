# frozen_string_literal: true

module Mutations
  class UpdateSubscription < BaseMutation
    description "Update subscription status from StoreKit 2 transaction"

    argument :product_id, String, required: true,
             description: "App Store product identifier"
    argument :original_transaction_id, String, required: true,
             description: "Original transaction ID from StoreKit 2"
    argument :status, String, required: true,
             description: "Subscription status: active, expired, revoked"
    argument :expires_at, GraphQL::Types::ISO8601DateTime, required: false,
             description: "Subscription expiration date"
    argument :purchased_at, GraphQL::Types::ISO8601DateTime, required: false,
             description: "Original purchase date"
    argument :environment, String, required: false, default_value: "production",
             description: "App Store environment: production, sandbox"

    field :success, Boolean, null: false
    field :subscription, Types::SubscriptionType, null: true
    field :error, String, null: true

    def resolve(product_id:, original_transaction_id:, status:, expires_at: nil, purchased_at: nil, environment: "production")
      authenticate_user!

      subscription = current_user.subscriptions.find_or_initialize_by(
        original_transaction_id: original_transaction_id
      )

      subscription.assign_attributes(
        product_id: product_id,
        status: status,
        expires_at: expires_at,
        purchased_at: purchased_at,
        environment: environment
      )

      if subscription.save
        Rails.logger.info("Subscription updated: user=#{current_user.id} product=#{product_id} status=#{status}")
        { success: true, subscription: subscription, error: nil }
      else
        { success: false, subscription: nil, error: subscription.errors.full_messages.join(", ") }
      end
    rescue StandardError => e
      Rails.logger.error("UpdateSubscription error: #{e.message}")
      { success: false, subscription: nil, error: "구독 정보 업데이트에 실패했습니다." }
    end
  end
end
