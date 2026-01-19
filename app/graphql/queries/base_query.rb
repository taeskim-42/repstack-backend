# frozen_string_literal: true

module Queries
  class BaseQuery < GraphQL::Schema::Resolver
    # Common functionality for all queries

    def current_user
      context[:current_user]
    end

    def authenticate_user!
      raise GraphQL::ExecutionError, "You need to sign in first" unless current_user
    end
  end
end
