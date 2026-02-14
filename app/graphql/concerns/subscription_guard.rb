# frozen_string_literal: true

module SubscriptionGuard
  extend ActiveSupport::Concern

  private

  # Raises GraphQL::ExecutionError if user is not at least Pro
  def require_pro!(feature_name = nil)
    return if current_user&.premium?

    message = if feature_name
      "#{feature_name}은(는) Pro 이상 구독이 필요합니다. 업그레이드해주세요!"
    else
      "Pro 이상 구독이 필요한 기능입니다."
    end

    raise GraphQL::ExecutionError, message
  end

  # Raises GraphQL::ExecutionError if user is not Max tier
  def require_max!(feature_name = nil)
    return if current_user&.max?

    message = if feature_name
      "#{feature_name}은(는) Max 전용 기능입니다. 업그레이드해주세요!"
    else
      "Max 구독이 필요한 기능입니다."
    end

    raise GraphQL::ExecutionError, message
  end

  # Backward compatibility alias
  def require_premium!(feature_name = nil)
    require_pro!(feature_name)
  end

  # Returns the current user's subscription tier (:free, :pro, :max)
  def subscription_tier
    current_user&.subscription_tier || :free
  end

  def premium?
    current_user&.premium? || false
  end

  def pro?
    current_user&.pro? || false
  end

  def max?
    current_user&.max? || false
  end
end
