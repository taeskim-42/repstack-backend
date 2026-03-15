# frozen_string_literal: true

module Types
  class TrainingMethodInfoType < Types::BaseObject
    description "Information about the training method"

    field :id, String, null: true
    field :name, String, null: true, description: "Training method name in user's locale"
    field :korean, String, null: true, deprecation_reason: "Use name instead"
    field :description, String, null: true
    field :work_duration, Integer, null: true, description: "For tabata: work duration in seconds"
    field :rest_duration, Integer, null: true, description: "For tabata: rest duration in seconds"
    field :rounds, Integer, null: true, description: "For tabata: number of rounds"

    def name
      locale = context[:locale] || "ko"
      method_id = object.is_a?(Hash) ? (object[:id] || object["id"]) : nil

      if method_id
        method_key = AiTrainer::Data::TrainingConstants::TRAINING_METHODS.find { |_, v| v[:id] == method_id }&.first
        Localizable.translate(:training_methods, method_key, locale) if method_key
      else
        korean_val = object.is_a?(Hash) ? (object[:korean] || object["korean"]) : nil
        korean_val
      end
    end
  end
end
