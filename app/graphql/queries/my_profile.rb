# frozen_string_literal: true

module Queries
  class MyProfile < GraphQL::Schema::Resolver
    description "Get current user's profile"

    type Types::UserProfileType, null: true

    def resolve
      user = context[:current_user]
      return nil unless user

      user.user_profile
    end
  end
end