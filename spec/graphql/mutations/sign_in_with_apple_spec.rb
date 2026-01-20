# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SignInWithApple, type: :request do
  let(:mutation) do
    <<~GQL
      mutation SignInWithApple($identityToken: String!, $userName: String) {
        signInWithApple(input: { identityToken: $identityToken, userName: $userName }) {
          authPayload {
            token
            user {
              id
              email
              name
            }
          }
          errors
        }
      }
    GQL
  end

  let(:identity_token) { "valid.apple.jwt.token" }
  let(:apple_user_id) { "001234.abcd5678.efgh" }
  let(:email) { "user@privaterelay.appleid.com" }
  let(:user_name) { "John Doe" }

  let(:apple_data) do
    {
      apple_user_id: apple_user_id,
      email: email,
      email_verified: true
    }
  end

  describe "successful sign in" do
    before do
      allow_any_instance_of(AppleSignInService).to receive(:verify).and_return(apple_data)
    end

    context "when user does not exist" do
      it "creates a new user and returns auth payload" do
        expect {
          post "/graphql", params: { query: mutation, variables: { identityToken: identity_token, userName: user_name } }
        }.to change(User, :count).by(1)

        json = JSON.parse(response.body)
        data = json.dig("data", "signInWithApple")

        expect(data["errors"]).to be_empty
        expect(data["authPayload"]["token"]).to be_present
        expect(data["authPayload"]["user"]["email"]).to eq(email)
        expect(data["authPayload"]["user"]["name"]).to eq(user_name)
      end

      it "uses email prefix as name when userName not provided" do
        post "/graphql", params: { query: mutation, variables: { identityToken: identity_token } }

        json = JSON.parse(response.body)
        data = json.dig("data", "signInWithApple")

        expect(data["authPayload"]["user"]["name"]).to eq("user")
      end
    end

    context "when user already exists with apple_user_id" do
      let!(:existing_user) { create(:user, :apple_user, apple_user_id: apple_user_id, email: email, name: "Existing User") }

      it "returns existing user without creating new one" do
        expect {
          post "/graphql", params: { query: mutation, variables: { identityToken: identity_token } }
        }.not_to change(User, :count)

        json = JSON.parse(response.body)
        data = json.dig("data", "signInWithApple")

        expect(data["errors"]).to be_empty
        expect(data["authPayload"]["user"]["id"]).to eq(existing_user.id.to_s)
        expect(data["authPayload"]["user"]["name"]).to eq("Existing User")
      end
    end

    context "when user exists with same email but no apple_user_id" do
      let!(:existing_user) { create(:user, email: email, name: "Email User") }

      it "links apple_user_id to existing user" do
        expect {
          post "/graphql", params: { query: mutation, variables: { identityToken: identity_token } }
        }.not_to change(User, :count)

        json = JSON.parse(response.body)
        data = json.dig("data", "signInWithApple")

        expect(data["errors"]).to be_empty
        expect(data["authPayload"]["user"]["id"]).to eq(existing_user.id.to_s)

        existing_user.reload
        expect(existing_user.apple_user_id).to eq(apple_user_id)
      end
    end
  end

  describe "failed sign in" do
    context "when token verification fails" do
      before do
        allow_any_instance_of(AppleSignInService).to receive(:verify)
          .and_raise(AppleSignInService::InvalidTokenError, "Token expired")
      end

      it "returns error message" do
        post "/graphql", params: { query: mutation, variables: { identityToken: identity_token } }

        json = JSON.parse(response.body)
        data = json.dig("data", "signInWithApple")

        expect(data["authPayload"]).to be_nil
        expect(data["errors"]).to include("Token expired")
      end
    end
  end
end
