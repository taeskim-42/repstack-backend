# frozen_string_literal: true

# Stores chat conversation history for context-aware AI responses
class ChatMessage < ApplicationRecord
  belongs_to :user

  ROLES = %w[user assistant].freeze

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :content, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :chronological, -> { order(created_at: :asc) }

  # Get recent messages for a user (for prompt caching)
  # Returns messages in chronological order for API
  def self.recent_for_user(user_id, limit: 10, session_id: nil)
    scope = where(user_id: user_id)
    scope = scope.for_session(session_id) if session_id.present?
    scope.order(created_at: :desc).limit(limit).reverse
  end

  # Convert to Claude API message format
  # cache_control must be inside content block, not at message level
  def to_api_format(cache: false)
    if cache
      {
        role: role,
        content: [
          {
            type: "text",
            text: content,
            cache_control: { type: "ephemeral" }
          }
        ]
      }
    else
      { role: role, content: content }
    end
  end

  # Build messages array for Claude API with caching
  # cache_limit default is 3 (Anthropic allows max 4 total, 1 reserved for system prompt)
  def self.build_api_messages(user_id, new_message, session_id: nil, cache_limit: 3)
    messages = []

    # Get recent history
    history = recent_for_user(user_id, limit: cache_limit, session_id: session_id)

    # Add history with caching on older messages
    history.each_with_index do |msg, idx|
      # Cache all but the last 2 messages (they change frequently)
      should_cache = idx < (history.length - 2)
      messages << msg.to_api_format(cache: should_cache)
    end

    # Add new user message (no cache - it's new)
    messages << { role: "user", content: new_message }

    messages
  end
end
