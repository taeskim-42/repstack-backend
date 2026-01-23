# frozen_string_literal: true

module Mutations
  class DevSignIn < BaseMutation
    description "Development/test sign in (disabled in production)"

    argument :email, String, required: false,
      description: "Email for test user (default: test@example.com)"
    argument :name, String, required: false,
      description: "Name for test user (default: Test User)"

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [ String ], null: false

    TOKEN_EXPIRY_HOURS = 24

    def resolve(email: nil, name: nil)
      # Only allow in development/test environments or when explicitly enabled
      unless Rails.env.development? || Rails.env.test? || ENV["ALLOW_DEV_SIGN_IN"] == "true"
        return { auth_payload: nil, errors: [ "devSignIn is only available in development/test environments" ] }
      end

      email ||= "test@example.com"
      name ||= "Test User"

      user = User.find_or_create_by!(email: email.downcase) do |u|
        u.name = name
        u.apple_user_id = "dev_#{SecureRandom.hex(8)}"
      end

      # Ensure user has a profile
      user.create_user_profile! unless user.user_profile

      expires_at = TOKEN_EXPIRY_HOURS.hours.from_now
      token = JsonWebToken.encode(user_id: user.id, exp: expires_at.to_i)

      {
        auth_payload: {
          token: token,
          user: user
        },
        errors: []
      }
    rescue ActiveRecord::RecordInvalid => e
      { auth_payload: nil, errors: [ e.message ] }
    end
  end
end
