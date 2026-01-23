# frozen_string_literal: true

module Mutations
  class DevSignInFresh < BaseMutation
    description "Create a fresh new user for testing (disabled in production). Always creates a new user with clean profile state."

    argument :email, String, required: false,
      description: "Email prefix for new user (will append timestamp)"
    argument :name, String, required: false,
      description: "Name for new user (default: New User)"

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [String], null: false

    TOKEN_EXPIRY_HOURS = 24

    def resolve(email: nil, name: nil)
      unless Rails.env.development? || Rails.env.test? || ENV["ALLOW_DEV_SIGN_IN"] == "true"
        return { auth_payload: nil, errors: ["devSignInFresh is only available in development/test environments"] }
      end

      timestamp = Time.current.to_i
      email_prefix = email&.split("@")&.first || "fresh_user"
      email = "#{email_prefix}_#{timestamp}@test.com"
      name ||= "New User"

      user = User.create!(
        email: email,
        name: name,
        apple_user_id: "fresh_#{SecureRandom.hex(8)}"
      )

      # Create profile with clean state (level_assessed_at = nil for level assessment flow)
      user.create_user_profile!(
        level_assessed_at: nil,
        fitness_factors: {}
      )

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
      { auth_payload: nil, errors: [e.message] }
    end
  end
end
