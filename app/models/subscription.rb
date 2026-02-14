# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  # Legacy product IDs (treated as Pro tier for backward compatibility)
  LEGACY_MONTHLY_PRODUCT_ID = "com.tskim.repstack.premium.monthly"
  LEGACY_YEARLY_PRODUCT_ID = "com.tskim.repstack.premium.yearly"

  # Pro tier product IDs ($6.99/month, $49.99/year)
  PRO_MONTHLY_PRODUCT_ID = "com.tskim.repstack.pro.monthly"
  PRO_YEARLY_PRODUCT_ID = "com.tskim.repstack.pro.yearly"

  # Max tier product IDs ($14.99/month, $99.99/year)
  MAX_MONTHLY_PRODUCT_ID = "com.tskim.repstack.max.monthly"
  MAX_YEARLY_PRODUCT_ID = "com.tskim.repstack.max.yearly"

  PRO_PRODUCT_IDS = [
    PRO_MONTHLY_PRODUCT_ID, PRO_YEARLY_PRODUCT_ID,
    LEGACY_MONTHLY_PRODUCT_ID, LEGACY_YEARLY_PRODUCT_ID
  ].freeze

  MAX_PRODUCT_IDS = [
    MAX_MONTHLY_PRODUCT_ID, MAX_YEARLY_PRODUCT_ID
  ].freeze

  VALID_PRODUCT_IDS = (PRO_PRODUCT_IDS + MAX_PRODUCT_IDS).freeze

  STATUSES = %w[active expired revoked billing_retry_period grace_period].freeze

  # Backward-compatible aliases
  MONTHLY_PRODUCT_ID = PRO_MONTHLY_PRODUCT_ID
  YEARLY_PRODUCT_ID = PRO_YEARLY_PRODUCT_ID

  validates :product_id, presence: true, inclusion: { in: VALID_PRODUCT_IDS }
  validates :original_transaction_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :for_user, ->(user) { where(user: user) }

  def active?
    status == "active" && (expires_at.nil? || expires_at > Time.current)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def grace_period?
    status == "grace_period" && expires_at.present? && expires_at > Time.current
  end

  # Returns :pro or :max based on product_id
  def tier
    if MAX_PRODUCT_IDS.include?(product_id)
      :max
    else
      :pro
    end
  end

  def pro?
    tier == :pro
  end

  def max?
    tier == :max
  end

  def monthly?
    product_id.end_with?(".monthly")
  end

  def yearly?
    product_id.end_with?(".yearly")
  end
end
