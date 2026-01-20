# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSignInService do
  let(:identity_token) { "valid.jwt.token" }
  let(:apple_user_id) { "001234.abcd5678.efgh" }
  let(:email) { "user@privaterelay.appleid.com" }
  let(:apple_client_id) { "com.example.app" }

  let(:mock_public_key) { OpenSSL::PKey::RSA.generate(2048) }

  let(:valid_payload) do
    {
      "iss" => "https://appleid.apple.com",
      "aud" => apple_client_id,
      "exp" => 1.hour.from_now.to_i,
      "iat" => Time.now.to_i,
      "sub" => apple_user_id,
      "email" => email,
      "email_verified" => true
    }
  end

  let(:apple_keys_response) do
    jwk = JWT::JWK.new(mock_public_key)
    { "keys" => [ jwk.export.merge("kid" => "test_kid") ] }
  end

  let(:faraday_success_response) do
    instance_double(Faraday::Response, success?: true, body: apple_keys_response.to_json)
  end

  let(:faraday_failure_response) do
    instance_double(Faraday::Response, success?: false, body: "Server Error")
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("APPLE_CLIENT_ID").and_return(apple_client_id)
  end

  describe "#verify" do
    context "with valid token" do
      let(:valid_token) do
        JWT.encode(
          valid_payload,
          mock_public_key,
          "RS256",
          { kid: "test_kid" }
        )
      end

      before do
        allow(Faraday).to receive(:get)
          .with(AppleSignInService::APPLE_KEYS_URL)
          .and_return(faraday_success_response)
      end

      it "returns apple user data" do
        service = described_class.new(valid_token)
        result = service.verify

        expect(result[:apple_user_id]).to eq(apple_user_id)
        expect(result[:email]).to eq(email)
        expect(result[:email_verified]).to be(true)
      end
    end

    context "with expired token" do
      let(:expired_payload) { valid_payload.merge("exp" => 1.hour.ago.to_i) }
      let(:expired_token) do
        JWT.encode(
          expired_payload,
          mock_public_key,
          "RS256",
          { kid: "test_kid" }
        )
      end

      before do
        allow(Faraday).to receive(:get)
          .with(AppleSignInService::APPLE_KEYS_URL)
          .and_return(faraday_success_response)
      end

      it "raises InvalidTokenError" do
        service = described_class.new(expired_token)

        expect { service.verify }.to raise_error(
          AppleSignInService::InvalidTokenError,
          /Token verification failed/
        )
      end
    end

    context "with invalid issuer" do
      let(:invalid_issuer_payload) { valid_payload.merge("iss" => "https://fake.apple.com") }
      let(:invalid_issuer_token) do
        JWT.encode(
          invalid_issuer_payload,
          mock_public_key,
          "RS256",
          { kid: "test_kid" }
        )
      end

      before do
        allow(Faraday).to receive(:get)
          .with(AppleSignInService::APPLE_KEYS_URL)
          .and_return(faraday_success_response)
      end

      it "raises InvalidTokenError" do
        service = described_class.new(invalid_issuer_token)

        expect { service.verify }.to raise_error(
          AppleSignInService::InvalidTokenError,
          /Token verification failed/
        )
      end
    end

    context "when public key not found" do
      let(:unknown_kid_token) do
        JWT.encode(
          valid_payload,
          mock_public_key,
          "RS256",
          { kid: "unknown_kid" }
        )
      end

      before do
        allow(Faraday).to receive(:get)
          .with(AppleSignInService::APPLE_KEYS_URL)
          .and_return(faraday_success_response)
      end

      it "raises InvalidTokenError" do
        service = described_class.new(unknown_kid_token)

        expect { service.verify }.to raise_error(
          AppleSignInService::InvalidTokenError,
          /Public key not found/
        )
      end
    end

    context "when Apple keys endpoint fails" do
      let(:valid_format_token) do
        JWT.encode(
          valid_payload,
          mock_public_key,
          "RS256",
          { kid: "test_kid" }
        )
      end

      before do
        allow(Faraday).to receive(:get)
          .with(AppleSignInService::APPLE_KEYS_URL)
          .and_return(faraday_failure_response)
      end

      it "raises InvalidTokenError" do
        service = described_class.new(valid_format_token)

        expect { service.verify }.to raise_error(
          AppleSignInService::InvalidTokenError,
          /Failed to fetch Apple public keys/
        )
      end
    end
  end
end
