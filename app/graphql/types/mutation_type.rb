# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :generate_routine, mutation: Mutations::GenerateRoutine
  end
end
