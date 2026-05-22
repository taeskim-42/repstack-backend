# frozen_string_literal: true

module Mutations
  class UpdateProfile < BaseMutation
    description "[DEPRECATED] Use updateUserProfile instead. Will be removed once App Store coverage allows."

    argument :profile_input, Types::UserProfileInputType, required: true

    field :user_profile, Types::UserProfileType, null: true
    field :errors, [ String ], null: false

    def resolve(profile_input:)
      with_error_handling(user_profile: nil) do
        user = authenticate!

        profile = user.user_profile || user.build_user_profile
        profile_attrs = profile_input.to_h.compact

        profile.update!(profile_attrs)
        success_response(user_profile: profile)
      end
    end
  end
end
