# frozen_string_literal: true

module Types
  class ChatPayloadType < Types::BaseObject
    description "Response from chat API"

    field :success, Boolean, null: false, description: "Whether the request was successful"
    field :message, String, null: true, description: "AI response message"
    field :intent, Types::ChatIntentEnum, null: true, description: "Classified user intent"
    field :data, Types::ChatDataType, null: true, description: "Intent-specific data"
    field :error, String, null: true, description: "Error message if any"
  end
end
