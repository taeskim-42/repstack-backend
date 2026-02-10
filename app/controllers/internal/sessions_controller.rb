# frozen_string_literal: true

# Internal API controller for Agent conversation history (Python Agent Service → Rails)
module Internal
  class SessionsController < BaseController
    before_action :set_session, only: [:messages, :save_messages, :summarize]

    # GET /internal/sessions/:user_id/messages
    # Returns conversation history for user's active agent session
    def messages
      unless @agent_session
        return render_success(messages: [], session_id: nil)
      end

      msgs = @agent_session.agent_conversation_messages.chronological.map do |m|
        { role: m.role, content: m.content, token_count: m.token_count, created_at: m.created_at }
      end

      render_success(
        messages: msgs,
        session_id: @agent_session.claude_session_id,
        total_tokens: @agent_session.agent_conversation_messages.total_tokens
      )
    end

    # POST /internal/sessions/:user_id/messages
    # Save new conversation messages to the active session
    # Params: { messages: [{ role: "user", content: "...", token_count: 0 }] }
    def save_messages
      # Auto-create session if none active
      @agent_session ||= AgentSession.create!(
        user: @user,
        claude_session_id: SecureRandom.uuid,
        status: "active",
        last_active_at: Time.current
      )

      incoming = params[:messages] || []
      saved = []

      incoming.each do |msg|
        record = @agent_session.agent_conversation_messages.create!(
          role: msg[:role],
          content: msg[:content],
          token_count: msg[:token_count] || 0
        )
        saved << record.id
      end

      @agent_session.touch_activity!

      render_success(
        saved_count: saved.size,
        session_id: @agent_session.claude_session_id,
        total_tokens: @agent_session.agent_conversation_messages.total_tokens
      )
    end

    # POST /internal/sessions/:user_id/summarize
    # Replace ALL messages with a compacted set (summary + recent messages)
    # Params: { messages: [{ role: "user", content: "...", token_count: 0 }] }
    def summarize
      unless @agent_session
        return render_error("No active session")
      end

      # Delete all existing messages
      @agent_session.agent_conversation_messages.delete_all

      # Insert the compacted message set
      incoming = params[:messages] || []
      incoming.each do |msg|
        @agent_session.agent_conversation_messages.create!(
          role: msg[:role],
          content: msg[:content],
          token_count: msg[:token_count] || 0
        )
      end

      render_success(
        total_tokens: @agent_session.agent_conversation_messages.total_tokens
      )
    end

    private

    def set_session
      @agent_session = @user.agent_sessions.active.order(last_active_at: :desc).first
    end
  end
end
