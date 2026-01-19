# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SignUp, type: :graphql do
  let(:mutation) do
    <<~GRAPHQL
      mutation SignUp($email: String!, $password: String!, $name: String!) {
        signUp(input: { email: $email, password: $password, name: $name }) {
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

  describe "successful signup" do
    let(:variables) do
      {
        email: "newuser@example.com",
        password: "password123",
        name: "New User"
      }
    end

    it "creates a new user" do
      expect {
        execute_graphql(query: mutation, variables: variables)
      }.to change(User, :count).by(1)
    end

    it "creates a user profile" do
      expect {
        execute_graphql(query: mutation, variables: variables)
      }.to change(UserProfile, :count).by(1)
    end

    it "returns auth payload with token" do
      response = execute_graphql(query: mutation, variables: variables)
      data = graphql_data(response)["signUp"]

      expect(data["errors"]).to be_empty
      expect(data["authPayload"]["token"]).to be_present
      expect(data["authPayload"]["user"]["email"]).to eq("newuser@example.com")
    end

    it "normalizes email to lowercase" do
      variables[:email] = "UPPERCASE@EXAMPLE.COM"
      response = execute_graphql(query: mutation, variables: variables)
      data = graphql_data(response)["signUp"]

      expect(data["authPayload"]["user"]["email"]).to eq("uppercase@example.com")
    end
  end

  describe "validation errors" do
    it "returns error for duplicate email" do
      create(:user, email: "existing@example.com")

      response = execute_graphql(
        query: mutation,
        variables: { email: "existing@example.com", password: "password123", name: "Test" }
      )
      data = graphql_data(response)["signUp"]

      expect(data["authPayload"]).to be_nil
      expect(data["errors"]).to include(match(/email/i))
    end

    it "returns error for short password" do
      response = execute_graphql(
        query: mutation,
        variables: { email: "test@example.com", password: "12345", name: "Test" }
      )

      expect(graphql_errors(response)).to be_present
    end

    it "returns error for invalid email format" do
      response = execute_graphql(
        query: mutation,
        variables: { email: "not-an-email", password: "password123", name: "Test" }
      )
      data = graphql_data(response)["signUp"]

      expect(data["authPayload"]).to be_nil
      expect(data["errors"]).not_to be_empty
    end
  end
end
