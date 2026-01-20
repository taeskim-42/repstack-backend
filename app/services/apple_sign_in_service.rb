# frozen_string_literal: true

class AppleSignInService
  APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
  APPLE_ISSUER = "https://appleid.apple.com"

  class InvalidTokenError < StandardError; end

  def initialize(identity_token)
    @identity_token = identity_token
  end

  def verify
    decoded_token = decode_and_verify_token
    {
      apple_user_id: decoded_token["sub"],
      email: decoded_token["email"],
      email_verified: decoded_token["email_verified"]
    }
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidIssuerError, JWT::InvalidAudError => e
    raise InvalidTokenError, "Token verification failed: #{e.message}"
  end

  private

  def decode_and_verify_token
    # Decode header without verification to get the key id
    header = JWT.decode(@identity_token, nil, false)[1]
    kid = header["kid"]

    # Find the matching public key
    public_key = find_public_key(kid)
    raise InvalidTokenError, "Public key not found for kid: #{kid}" unless public_key

    # Decode and verify the token
    decoded = JWT.decode(
      @identity_token,
      public_key,
      true,
      {
        algorithm: "RS256",
        iss: APPLE_ISSUER,
        verify_iss: true,
        aud: apple_client_id,
        verify_aud: true
      }
    )

    decoded[0]
  end

  def find_public_key(kid)
    keys = fetch_apple_public_keys
    key_data = keys.find { |key| key["kid"] == kid }
    return nil unless key_data

    jwk = JWT::JWK.new(key_data)
    jwk.public_key
  end

  def fetch_apple_public_keys
    response = Faraday.get(APPLE_KEYS_URL)
    raise InvalidTokenError, "Failed to fetch Apple public keys" unless response.success?

    JSON.parse(response.body)["keys"]
  end

  def apple_client_id
    ENV.fetch("APPLE_CLIENT_ID") { Rails.application.credentials.dig(:apple, :client_id) }
  end
end
