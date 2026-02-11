# frozen_string_literal: true

class AppleTokenService
  APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
  APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"

  class TokenError < StandardError; end

  # Exchange authorization_code for refresh_token
  def self.exchange_code(authorization_code)
    response = Faraday.post(APPLE_TOKEN_URL, {
      client_id: client_id,
      client_secret: generate_client_secret,
      code: authorization_code,
      grant_type: "authorization_code"
    })

    body = JSON.parse(response.body)

    unless response.success?
      Rails.logger.warn("[AppleTokenService] Code exchange failed: #{body}")
      return nil
    end

    body["refresh_token"]
  rescue StandardError => e
    Rails.logger.warn("[AppleTokenService] Code exchange error: #{e.message}")
    nil
  end

  # Revoke refresh_token (for account deletion)
  def self.revoke_token(refresh_token)
    response = Faraday.post(APPLE_REVOKE_URL, {
      client_id: client_id,
      client_secret: generate_client_secret,
      token: refresh_token,
      token_type_hint: "refresh_token"
    })

    if response.success?
      Rails.logger.info("[AppleTokenService] Token revoked successfully")
      true
    else
      Rails.logger.warn("[AppleTokenService] Revocation failed: #{response.status} #{response.body}")
      false
    end
  rescue StandardError => e
    Rails.logger.warn("[AppleTokenService] Revocation error: #{e.message}")
    false
  end

  def self.generate_client_secret
    team_id = ENV.fetch("APPLE_TEAM_ID")
    key_id = ENV.fetch("APPLE_KEY_ID")
    private_key_content = ENV.fetch("APPLE_PRIVATE_KEY")

    # Handle escaped newlines from environment variables
    private_key = OpenSSL::PKey::EC.new(private_key_content.gsub("\\n", "\n"))

    now = Time.now.to_i
    payload = {
      iss: team_id,
      iat: now,
      exp: now + 15_777_000, # ~6 months
      aud: "https://appleid.apple.com",
      sub: client_id
    }

    JWT.encode(payload, private_key, "ES256", { kid: key_id })
  end

  def self.client_id
    ENV.fetch("APPLE_CLIENT_ID") { Rails.application.credentials.dig(:apple, :client_id) }
  end

  private_class_method :generate_client_secret, :client_id
end
