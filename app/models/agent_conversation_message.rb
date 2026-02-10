# frozen_string_literal: true

class AgentConversationMessage < ApplicationRecord
  belongs_to :agent_session

  validates :role, presence: true, inclusion: { in: %w[user assistant tool_result] }
  validates :content, presence: true

  scope :chronological, -> { order(:created_at) }

  def self.total_tokens
    sum(:token_count)
  end
end
