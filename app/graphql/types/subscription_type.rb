# frozen_string_literal: true

module Types
  class SubscriptionType < Types::BaseObject
    field :id, ID, null: false
    field :product_id, String, null: false
    field :status, String, null: false
    field :tier, String, null: false, description: "Subscription tier: pro or max"
    field :expires_at, GraphQL::Types::ISO8601DateTime, null: true
    field :purchased_at, GraphQL::Types::ISO8601DateTime, null: true
    field :environment, String, null: false
    field :is_active, Boolean, null: false
    field :is_monthly, Boolean, null: false
    field :is_yearly, Boolean, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def is_active
      object.active?
    end

    def tier
      object.tier.to_s
    end

    def is_monthly
      object.monthly?
    end

    def is_yearly
      object.yearly?
    end
  end
end
