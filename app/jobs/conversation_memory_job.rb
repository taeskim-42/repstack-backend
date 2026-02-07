# frozen_string_literal: true

# Async job to extract conversation memories after session ends.
# Triggered when a new session starts (previous session > 30min idle).
class ConversationMemoryJob
  include Sidekiq::Job

  sidekiq_options queue: :low, retry: 1

  def perform(user_id, session_id)
    user = User.find_by(id: user_id)
    return unless user

    # Idempotency check
    profile = user.user_profile
    return unless profile
    return if profile.fitness_factors&.dig("last_memory_session_id") == session_id

    ConversationMemoryService.extract(user: user, session_id: session_id)
  end
end
