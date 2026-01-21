# frozen_string_literal: true

module Types
  class ChatInputType < Types::BaseInputObject
    graphql_name "ChatMessageInput"
    description "Input for chat API"

    argument :message, String, required: true, description: "User message (natural language)"
    argument :routine_id, ID, required: false, description: "Current routine ID (for context)"
    argument :session_id, String, required: false, description: "Chat session ID (for continuous conversation)"
  end
end
