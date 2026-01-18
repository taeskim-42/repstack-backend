# frozen_string_literal: true

module Mutations
  class SignUp < BaseMutation
    argument :email, String, required: true
    argument :password, String, required: true
    argument :name, String, required: true

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [String], null: false

    def resolve(email:, name:, password:)
      user = User.new(
        email: email,
        name: name,
        password: password,
        password_confirmation: password
      )

      if user.save
        # Create user profile
        user.create_user_profile!

        # Generate token
        expires_at = 24.hours.from_now
        token = JsonWebToken.encode(user_id: user.id, exp: expires_at.to_i)

        {
          auth_payload: {
            token: token,
            user: user
          },
          errors: []
        }
      else
        {
          auth_payload: nil,
          errors: user.errors.full_messages
        }
      end
    rescue StandardError => e
      {
        auth_payload: nil,
        errors: [e.message]
      }
    end
  end
end