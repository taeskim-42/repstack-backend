# frozen_string_literal: true

module Queries
  class Me < BaseQuery
    description "Get current user information"

    type Types::UserType, null: true

    def resolve
      authenticate_user!
      current_user
    end
  end
end
