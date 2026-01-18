# frozen_string_literal: true

module Mutations
  class SignIn < BaseMutation
    argument :email, String, required: true
    argument :password, String, required: true

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [String], null: false

    def resolve(email:, password:)
      user = User.find_by(email: email.downcase)

      if user&.authenticate(password)
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
          errors: ['Invalid email or password']
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