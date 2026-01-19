# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SignIn, type: :graphql do
  let(:mutation) do
    <<~GRAPHQL
      mutation SignIn($email: String!, $password: String!) {
        signIn(input: { email: $email, password: $password }) {
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

  let!(:user) { create(:user, email: "test@example.com", password: "password123") }

  describe "successful login" do
    let(:variables) do
      { email: "test@example.com", password: "password123" }
    end

    it "returns auth payload with token" do
      response = execute_graphql(query: mutation, variables: variables)
      data = graphql_data(response)["signIn"]

      expect(data["errors"]).to be_empty
      expect(data["authPayload"]["token"]).to be_present
      expect(data["authPayload"]["user"]["id"]).to eq(user.id.to_s)
    end

    it "accepts email in different case" do
      response = execute_graphql(
        query: mutation,
        variables: { email: "TEST@EXAMPLE.COM", password: "password123" }
      )
      data = graphql_data(response)["signIn"]

      expect(data["errors"]).to be_empty
      expect(data["authPayload"]["user"]["id"]).to eq(user.id.to_s)
    end

    it "generates a valid JWT token" do
      response = execute_graphql(query: mutation, variables: variables)
      token = graphql_data(response)["signIn"]["authPayload"]["token"]

      decoded = JsonWebToken.decode(token)
      expect(decoded[:user_id]).to eq(user.id)
    end
  end

  describe "failed login" do
    it "returns error for wrong password" do
      response = execute_graphql(
        query: mutation,
        variables: { email: "test@example.com", password: "wrongpassword" }
      )
      data = graphql_data(response)["signIn"]

      expect(data["authPayload"]).to be_nil
      expect(data["errors"]).to include("Invalid email or password")
    end

    it "returns error for non-existent user" do
      response = execute_graphql(
        query: mutation,
        variables: { email: "nonexistent@example.com", password: "password123" }
      )
      data = graphql_data(response)["signIn"]

      expect(data["authPayload"]).to be_nil
      expect(data["errors"]).to include("Invalid email or password")
    end

    it "does not reveal whether email exists" do
      wrong_email_response = execute_graphql(
        query: mutation,
        variables: { email: "wrong@example.com", password: "password123" }
      )

      wrong_password_response = execute_graphql(
        query: mutation,
        variables: { email: "test@example.com", password: "wrongpassword" }
      )

      # Both should return the same generic error message
      expect(
        graphql_data(wrong_email_response)["signIn"]["errors"]
      ).to eq(
        graphql_data(wrong_password_response)["signIn"]["errors"]
      )
    end
  end
end
