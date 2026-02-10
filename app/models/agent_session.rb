# frozen_string_literal: true

class AgentSession < ApplicationRecord
  belongs_to :user

  validates :claude_session_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[active expired compacted] }

  scope :active, -> { where(status: "active") }
  scope :expired, -> { where(status: "expired") }
  scope :stale, ->(duration = 30.minutes) { where("last_active_at < ?", duration.ago) }

  def active?
    status == "active"
  end

  def touch_activity!
    update!(last_active_at: Time.current)
  end

  def expire!
    update!(status: "expired")
  end

  def record_usage!(tokens:, cost_usd:)
    increment!(:message_count)
    increment!(:total_tokens, tokens)
    update!(total_cost_usd: total_cost_usd + cost_usd, last_active_at: Time.current)
  end
end
