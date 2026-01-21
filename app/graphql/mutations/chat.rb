# frozen_string_literal: true

module Mutations
  class Chat < BaseMutation
    description "ChatGPT-style conversational AI trainer endpoint"

    argument :input, Types::ChatInputType, required: true

    field :success, Boolean, null: false
    field :message, String, null: true
    field :intent, Types::ChatIntentEnum, null: true
    field :data, Types::ChatDataType, null: true
    field :error, String, null: true

    def resolve(input:)
      authenticate_user!

      result = ChatService.process(
        user: current_user,
        message: input[:message],
        routine_id: input[:routine_id],
        session_id: input[:session_id]
      )

      {
        success: result[:success],
        message: result[:message],
        intent: result[:intent],
        data: result[:data],
        error: result[:error]
      }
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
