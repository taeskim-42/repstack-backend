# frozen_string_literal: true

module Mutations
  class Chat < BaseMutation
    description "ChatGPT-style conversational AI trainer endpoint"

    argument :message, String, required: true, description: "User message (natural language)"
    argument :routine_id, ID, required: false, description: "Current routine ID (for context)"
    argument :session_id, String, required: false, description: "Chat session ID (for continuous conversation)"

    field :success, Boolean, null: false
    field :message, String, null: true
    field :intent, Types::ChatIntentEnum, null: true
    field :data, Types::ChatDataType, null: true
    field :error, String, null: true

    def resolve(message:, routine_id: nil, session_id: nil)
      authenticate_user!

      result = ChatService.process(
        user: current_user,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      )

      {
        success: result[:success],
        message: result[:message],
        intent: result[:intent],
        data: result[:data],
        error: result[:error]
      }
    rescue GraphQL::ExecutionError
      raise
    rescue StandardError => e
      Rails.logger.error("Chat mutation error: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))

      {
        success: false,
        message: nil,
        intent: nil,
        data: nil,
        error: "채팅 처리 중 오류가 발생했습니다: #{e.message}"
      }
    end
  end
end
