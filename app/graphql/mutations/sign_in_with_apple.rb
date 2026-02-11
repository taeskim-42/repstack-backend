# frozen_string_literal: true

module Mutations
  class SignInWithApple < BaseMutation
    description "Authenticate user with Apple Sign In and return access token"

    argument :identity_token, String, required: true, description: "Apple identity token (JWT)"
    argument :user_name, String, required: false, description: "User's name (only provided on first sign in)"

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [ String ], null: false

    TOKEN_EXPIRY_HOURS = 24

    def resolve(identity_token:, user_name: nil)
      with_error_handling(auth_payload: nil) do
        apple_data = verify_apple_token(identity_token)
        return error_response(apple_data[:error], auth_payload: nil) if apple_data[:error]

        user = find_or_create_user(apple_data, user_name)
        token = generate_token(user)

        MetricsService.record_login(success: true)

        success_response(
          auth_payload: { token: token, user: user }
        )
      end
    end

    private

    def verify_apple_token(identity_token)
      service = AppleSignInService.new(identity_token)
      service.verify
    rescue AppleSignInService::InvalidTokenError => e
      MetricsService.record_login(success: false)
      track_auth_failure
      { error: e.message }
    end

    def track_auth_failure
      ip = context[:request]&.ip
      return unless ip

      Rails.cache.increment("auth_failure:#{ip}", 1, expires_in: 5.minutes)
    end

    def find_or_create_user(apple_data, user_name)
      User.find_or_create_from_apple(
        apple_user_id: apple_data[:apple_user_id],
        email: apple_data[:email],
        name: user_name
      )
    end

    def generate_token(user)
      expires_at = TOKEN_EXPIRY_HOURS.hours.from_now
      JsonWebToken.encode(user_id: user.id, exp: expires_at.to_i)
    end
  end
end
