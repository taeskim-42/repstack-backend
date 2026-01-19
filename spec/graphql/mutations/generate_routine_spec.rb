# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::GenerateRoutine, type: :graphql do
  let(:mutation) do
    <<~GRAPHQL
      mutation GenerateRoutine($level: String!, $week: Int!, $day: Int!) {
        generateRoutine(input: { level: $level, week: $week, day: $day }) {
          routine {
            workoutType
            dayOfWeek
            estimatedDuration
            exercises {
              exerciseName
              targetMuscle
              sets
              reps
            }
          }
          errors
          isMock
        }
      }
    GRAPHQL
  end

  let(:valid_variables) do
    { level: "beginner", week: 1, day: 1 }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
  end

  describe "without API key" do
    before do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
    end

    it "returns mock data" do
      response = execute_graphql(query: mutation, variables: valid_variables)
      data = graphql_data(response)["generateRoutine"]

      expect(data["errors"]).to be_empty
      expect(data["isMock"]).to be true
      expect(data["routine"]).to be_present
      expect(data["routine"]["exercises"]).not_to be_empty
    end
  end

  describe "with API key" do
    let(:api_key) { "test-api-key" }
    let(:mock_api_response) do
      {
        "content" => [{
          "text" => {
            "workoutType" => "strength",
            "dayOfWeek" => "MONDAY",
            "estimatedDuration" => 45,
            "exercises" => [
              {
                "exerciseName" => "푸시업",
                "targetMuscle" => "chest",
                "sets" => 3,
                "reps" => 10,
                "weight" => nil,
                "weightDescription" => "체중",
                "bpm" => 30,
                "setDurationSeconds" => 45,
                "restDurationSeconds" => 60,
                "rangeOfMotion" => "full",
                "howTo" => "바닥에 엎드려...",
                "purpose" => "가슴 근력 강화"
              }
            ]
          }.to_json
        }]
      }
    end

    before do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(api_key)
      stub_request(:post, ClaudeApiService::API_URL)
        .to_return(
          status: 200,
          body: mock_api_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns generated routine" do
      response = execute_graphql(query: mutation, variables: valid_variables)
      data = graphql_data(response)["generateRoutine"]

      expect(data["errors"]).to be_empty
      expect(data["isMock"]).to be false
      expect(data["routine"]["workoutType"]).to eq("strength")
    end

    it "transforms exercise data correctly" do
      response = execute_graphql(query: mutation, variables: valid_variables)
      exercise = graphql_data(response)["generateRoutine"]["routine"]["exercises"].first

      expect(exercise["exerciseName"]).to eq("푸시업")
      expect(exercise["targetMuscle"]).to eq("chest")
      expect(exercise["sets"]).to eq(3)
      expect(exercise["reps"]).to eq(10)
    end
  end

  describe "parameter validation" do
    before do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("key")
    end

    it "rejects invalid level" do
      response = execute_graphql(
        query: mutation,
        variables: { level: "invalid", week: 1, day: 1 }
      )
      data = graphql_data(response)["generateRoutine"]

      expect(data["routine"]).to be_nil
      expect(data["errors"]).not_to be_empty
    end

    it "rejects week out of range" do
      response = execute_graphql(
        query: mutation,
        variables: { level: "beginner", week: 100, day: 1 }
      )
      data = graphql_data(response)["generateRoutine"]

      expect(data["routine"]).to be_nil
      expect(data["errors"]).not_to be_empty
    end

    it "rejects day out of range" do
      response = execute_graphql(
        query: mutation,
        variables: { level: "beginner", week: 1, day: 10 }
      )
      data = graphql_data(response)["generateRoutine"]

      expect(data["routine"]).to be_nil
      expect(data["errors"]).not_to be_empty
    end
  end

  describe "with body info" do
    let(:mutation_with_body_info) do
      <<~GRAPHQL
        mutation GenerateRoutine($level: String!, $week: Int!, $day: Int!, $bodyInfo: BodyInfoInput) {
          generateRoutine(input: { level: $level, week: $week, day: $day, bodyInfo: $bodyInfo }) {
            routine {
              workoutType
            }
            errors
          }
        }
      GRAPHQL
    end

    before do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
    end

    it "accepts body info parameters" do
      response = execute_graphql(
        query: mutation_with_body_info,
        variables: {
          level: "beginner",
          week: 1,
          day: 1,
          bodyInfo: { height: 175, weight: 70, bodyFat: 15 }
        }
      )
      data = graphql_data(response)["generateRoutine"]

      expect(data["errors"]).to be_empty
      expect(data["routine"]).to be_present
    end
  end
end
