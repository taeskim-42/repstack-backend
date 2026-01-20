# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::DevSignIn, type: :graphql do
  let(:mutation) do
    <<~GRAPHQL
      mutation DevSignIn($email: String, $name: String) {
        devSignIn(input: { email: $email, name: $name }) {
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
    GRAPHQL
  end

  describe "in test environment" do
    it "creates a new user with default values" do
      result = execute_graphql(query: mutation)

      data = result["data"]["devSignIn"]
      expect(data["errors"]).to be_empty
      expect(data["authPayload"]["token"]).to be_present
      expect(data["authPayload"]["user"]["email"]).to eq("test@example.com")
      expect(data["authPayload"]["user"]["name"]).to eq("Test User")
    end

    it "creates a new user with custom email and name" do
      result = execute_graphql(
        query: mutation,
        variables: { email: "custom@test.com", name: "Custom User" }
      )

      data = result["data"]["devSignIn"]
      expect(data["errors"]).to be_empty
      expect(data["authPayload"]["user"]["email"]).to eq("custom@test.com")
      expect(data["authPayload"]["user"]["name"]).to eq("Custom User")
    end

    it "returns existing user if email already exists" do
      existing_user = create(:user, email: "existing@test.com", name: "Existing")

      result = execute_graphql(
        query: mutation,
        variables: { email: "existing@test.com" }
      )

      data = result["data"]["devSignIn"]
      expect(data["errors"]).to be_empty
      expect(data["authPayload"]["user"]["email"]).to eq(existing_user.email)
    end

    it "creates user profile automatically" do
      result = execute_graphql(
        query: mutation,
        variables: { email: "newuser@test.com" }
      )

      data = result["data"]["devSignIn"]
      expect(data["errors"]).to be_empty

      user = User.find_by(email: "newuser@test.com")
      expect(user.user_profile).to be_present
    end

    it "returns valid JWT token" do
      result = execute_graphql(query: mutation)

      token = result["data"]["devSignIn"]["authPayload"]["token"]
      decoded = JsonWebToken.decode(token)
      expect(decoded).to be_present
      expect(decoded["user_id"]).to be_present
    end
  end
end
