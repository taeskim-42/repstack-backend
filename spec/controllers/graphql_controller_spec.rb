# frozen_string_literal: true

require "rails_helper"

RSpec.describe GraphqlController, type: :request do
  let(:headers) { { "Content-Type" => "application/json" } }

  describe "POST /graphql" do
    context "with valid query" do
      let(:query) do
        <<~GRAPHQL
          query {
            __schema {
              queryType { name }
            }
          }
        GRAPHQL
      end

      it "executes the query successfully" do
        post "/graphql", params: { query: query }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["data"]["__schema"]["queryType"]["name"]).to eq("Query")
      end
    end

    context "with mutation" do
      let(:mutation) do
        <<~GRAPHQL
          mutation SignInWithApple($identityToken: String!, $userName: String) {
            signInWithApple(input: { identityToken: $identityToken, userName: $userName }) {
              authPayload { token }
              errors
            }
          }
        GRAPHQL
      end

      let(:apple_data) do
        {
          apple_user_id: "test.apple.user.id",
          email: "graphql-controller-test@example.com",
          email_verified: true
        }
      end

      before do
        allow_any_instance_of(AppleSignInService).to receive(:verify).and_return(apple_data)
      end

      it "executes mutation with variables" do
        variables = {
          identityToken: "mock.apple.token",
          userName: "GraphQL Test"
        }

        post "/graphql",
             params: { query: mutation, variables: variables }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["data"]["signInWithApple"]["authPayload"]["token"]).to be_present
      end
    end

    context "with authenticated request" do
      let(:user) { create(:user) }
      let(:token) { JsonWebToken.encode(user_id: user.id) }
      let(:auth_headers) { headers.merge("Authorization" => "Bearer #{token}") }

      let(:query) do
        <<~GRAPHQL
          query {
            me {
              id
              email
            }
          }
        GRAPHQL
      end

      it "includes current user in context" do
        post "/graphql", params: { query: query }.to_json, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["data"]["me"]["email"]).to eq(user.email)
      end
    end

    context "with no authentication" do
      let(:query) { "query { health }" }

      it "allows unauthenticated queries to public fields" do
        post "/graphql", params: { query: query }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["data"]["health"]).to eq("ok")
      end
    end

    context "with syntax error in query" do
      let(:invalid_query) { "query { invalid syntax {{" }

      it "returns error response" do
        post "/graphql", params: { query: invalid_query }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
      end
    end

    context "with empty query" do
      it "handles empty query" do
        post "/graphql", params: { query: "" }.to_json, headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
      end
    end

    context "with operation name" do
      let(:query) do
        <<~GRAPHQL
          query GetSchema {
            __schema { queryType { name } }
          }
          query GetHealth {
            health
          }
        GRAPHQL
      end

      it "executes specific operation" do
        post "/graphql",
             params: { query: query, operationName: "GetSchema" }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["data"]["__schema"]["queryType"]["name"]).to eq("Query")
      end
    end

    context "with request ID" do
      let(:query) { "query { health }" }
      let(:request_id) { "test-request-#{SecureRandom.uuid}" }

      it "returns request ID in response headers" do
        post "/graphql",
             params: { query: query }.to_json,
             headers: headers.merge("X-Request-ID" => request_id)

        expect(response.headers["X-Request-ID"]).to eq(request_id)
      end
    end
  end
end
