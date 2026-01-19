# frozen_string_literal: true

module Mutations
  class SignUp < BaseMutation
    description "Create a new user account"

    argument :email, String, required: true
    argument :password, String, required: true
    argument :name, String, required: true

    field :auth_payload, Types::AuthPayloadType, null: true
    field :errors, [String], null: false

    PASSWORD_MIN_LENGTH = 6
    TOKEN_EXPIRY_HOURS = 24

    def resolve(email:, name:, password:)
      with_error_handling(auth_payload: nil) do
        user = User.new(
          email: email.strip.downcase,
          name: name.strip,
          password: password,
          password_confirmation: password
        )

        ActiveRecord::Base.transaction do
          user.save!
          user.create_user_profile!
        end

        token = generate_token(user)
        MetricsService.record_signup(success: true)

        success_response(
          auth_payload: { token: token, user: user }
        )
      rescue StandardError => e
        MetricsService.record_signup(success: false)
        raise e
      end
    end

    private

    def ready?(password:, **args)
      if password.length < PASSWORD_MIN_LENGTH
        raise GraphQL::ExecutionError, "Password must be at least #{PASSWORD_MIN_LENGTH} characters"
      end
      true
    end

    def generate_token(user)
      expires_at = TOKEN_EXPIRY_HOURS.hours.from_now
      JsonWebToken.encode(user_id: user.id, exp: expires_at.to_i)
    end
  end
end