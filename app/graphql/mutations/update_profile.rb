# frozen_string_literal: true

module Mutations
  class UpdateProfile < BaseMutation
    argument :profile_input, Types::UserProfileInputType, required: true

    field :user_profile, Types::UserProfileType, null: true
    field :errors, [String], null: false

    def resolve(profile_input:)
      user = context[:current_user]
      
      unless user
        return {
          user_profile: nil,
          errors: ['Authentication required']
        }
      end

      profile = user.user_profile || user.build_user_profile

      # Convert input to hash and filter out nil values
      profile_attrs = profile_input.to_h.compact

      if profile.update(profile_attrs)
        {
          user_profile: profile,
          errors: []
        }
      else
        {
          user_profile: nil,
          errors: profile.errors.full_messages
        }
      end
    rescue StandardError => e
      {
        user_profile: nil,
        errors: [e.message]
      }
    end
  end
end