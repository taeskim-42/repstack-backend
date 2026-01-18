# frozen_string_literal: true

module Queries
  class Me < GraphQL::Schema::Resolver
    description "Get current user information"

    type Types::UserType, null: true

    def resolve
      context[:current_user]
    end
  end
end