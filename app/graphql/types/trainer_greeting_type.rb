# frozen_string_literal: true

module Types
  class TrainerGreetingType < Types::BaseObject
    description "AI trainer greeting response"

    field :success, Boolean, null: false, description: "Whether the request was successful"
    field :message, String, null: true, description: "Trainer greeting message"
    field :intent, Types::ChatIntentEnum, null: true, description: "Suggested next action intent"
    field :data, Types::ChatDataType, null: true, description: "Additional context data"
    field :error, String, null: true, description: "Error message if any"
  end
end
