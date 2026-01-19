# frozen_string_literal: true

module Mutations
  class SignIn < BaseMutation
    description "Authenticate user and return access token"

    argument :email, String, required: true
    argument :password, String, required: true

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [String], null: false

    TOKEN_EXPIRY_HOURS = 24
    INVALID_CREDENTIALS_MESSAGE = "Invalid email or password"

    def resolve(email:, password:)
      with_error_handling(auth_payload: nil) do
        user = User.find_by(email: email.strip.downcase)

        unless user&.authenticate(password)
          MetricsService.record_login(success: false)
          return error_response(INVALID_CREDENTIALS_MESSAGE, auth_payload: nil)
        end

        token = generate_token(user)
        MetricsService.record_login(success: true)

        success_response(
          auth_payload: { token: token, user: user }
        )
      end
    end

    private

    def generate_token(user)
      expires_at = TOKEN_EXPIRY_HOURS.hours.from_now
      JsonWebToken.encode(user_id: user.id, exp: expires_at.to_i)
    end
  end
end