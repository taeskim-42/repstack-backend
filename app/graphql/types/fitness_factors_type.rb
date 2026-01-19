# frozen_string_literal: true

module Types
  class FitnessFactorsType < Types::BaseObject
    description "Fitness factors assessment"

    field :strength, Float, null: false, description: "Strength score 0-10"
    field :endurance, Float, null: false, description: "Endurance score 0-10"
    field :flexibility, Float, null: false, description: "Flexibility score 0-10"
    field :balance, Float, null: false, description: "Balance score 0-10"
    field :coordination, Float, null: false, description: "Coordination score 0-10"
  end
end
