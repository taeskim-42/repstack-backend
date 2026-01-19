# frozen_string_literal: true

module Types
  class TrainingMethodInfoType < Types::BaseObject
    description "Information about the training method"

    field :id, String, null: true
    field :korean, String, null: true
    field :description, String, null: true
    field :work_duration, Integer, null: true, description: "For tabata: work duration in seconds"
    field :rest_duration, Integer, null: true, description: "For tabata: rest duration in seconds"
    field :rounds, Integer, null: true, description: "For tabata: number of rounds"
  end
end
