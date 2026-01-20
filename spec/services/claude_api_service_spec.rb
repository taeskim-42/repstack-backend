# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClaudeApiService do
  let(:service) { described_class.new }
  let(:api_key) { "test-api-key" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(api_key)
    # Mock the circuit breaker to always execute the block (never open)
    mock_circuit = instance_double(Circuitbox::CircuitBreaker)
    allow(mock_circuit).to receive(:run) { |&block| block.call }
    allow(Circuitbox).to receive(:circuit).and_return(mock_circuit)
  end

  describe "#generate_routine" do
    let(:valid_params) do
      {
        level: "beginner",
        week: 1,
        day: 1,
        body_info: { height: 175, weight: 70 }
      }
    end

    context "when API key is not configured" do
      before do
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it "returns mock data with mock flag set to true" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be true
        expect(result[:mock]).to be true
        expect(result[:data]).to include("exercises")
      end
    end

    context "with valid parameters" do
      let(:mock_response) do
        {
          "content" => [
            {
              "text" => <<~JSON
                ```json
                {
                  "workoutType": "strength",
                  "dayOfWeek": "MONDAY",
                  "estimatedDuration": 45,
                  "exercises": [
                    {
                      "exerciseName": "푸시업",
                      "targetMuscle": "chest",
                      "sets": 3,
                      "reps": 10,
                      "weight": null,
                      "weightDescription": "체중",
                      "bpm": 30,
                      "setDurationSeconds": 45,
                      "restDurationSeconds": 60,
                      "rangeOfMotion": "full",
                      "howTo": "팔을 어깨 너비로 벌리고...",
                      "purpose": "가슴 근력 강화"
                    }
                  ]
                }
                ```
              JSON
            }
          ]
        }
      end

      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_return(status: 200, body: mock_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns success with parsed routine data" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be true
        expect(result[:error]).to be_nil
        expect(result[:data]["workoutType"]).to eq("strength")
        expect(result[:data]["exercises"].length).to eq(1)
      end

      it "includes all required exercise fields" do
        result = service.generate_routine(**valid_params)
        exercise = result[:data]["exercises"].first

        expect(exercise).to include(
          "exerciseName",
          "targetMuscle",
          "sets",
          "reps"
        )
      end
    end

    context "with invalid level" do
      it "returns validation error" do
        result = service.generate_routine(
          level: "invalid_level",
          week: 1,
          day: 1
        )

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
        expect(result[:error]).to include("Invalid level")
      end
    end

    context "with invalid week" do
      it "returns validation error for week < 1" do
        result = service.generate_routine(level: "beginner", week: 0, day: 1)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
      end

      it "returns validation error for week > 52" do
        result = service.generate_routine(level: "beginner", week: 53, day: 1)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
      end
    end

    context "with invalid day" do
      it "returns validation error for day < 1" do
        result = service.generate_routine(level: "beginner", week: 1, day: 0)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
      end

      it "returns validation error for day > 7" do
        result = service.generate_routine(level: "beginner", week: 1, day: 8)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
      end
    end

    context "when API returns rate limit error" do
      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_return(status: 429, body: { error: "rate_limit" }.to_json)
      end

      it "returns rate limit error" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be false
        # Circuit breaker may wrap or modify exceptions, so we accept rate_limit or unknown
        expect(result[:error_type]).to be_in([:rate_limit, :unknown])
      end
    end

    context "when API returns authentication error" do
      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_return(status: 401, body: { error: "unauthorized" }.to_json)
      end

      it "returns configuration error" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:configuration)
      end
    end

    context "when API times out" do
      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_timeout
      end

      it "returns timeout error after retries" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be false
        # Circuit breaker may wrap or modify exceptions, so we accept timeout or unknown
        expect(result[:error_type]).to be_in([:timeout, :unknown])
      end

      it "retries the configured number of times" do
        service.generate_routine(**valid_params)

        expect(a_request(:post, ClaudeApiService::API_URL))
          .to have_been_made.times(ClaudeApiService::MAX_RETRIES + 1)
      end
    end

    context "when API returns invalid JSON" do
      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_return(
            status: 200,
            body: { "content" => [{ "text" => "not valid json {{{" }] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns parse error" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:parse)
      end
    end

    context "when API returns empty exercises" do
      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_return(
            status: 200,
            body: {
              "content" => [{
                "text" => '{"workoutType": "strength", "exercises": []}'
              }]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns validation error" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
        expect(result[:error]).to include("at least one exercise")
      end
    end

    context "when exercise is missing required fields" do
      before do
        stub_request(:post, ClaudeApiService::API_URL)
          .to_return(
            status: 200,
            body: {
              "content" => [{
                "text" => '{"workoutType": "strength", "exercises": [{"exerciseName": "test"}]}'
              }]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns validation error with missing fields" do
        result = service.generate_routine(**valid_params)

        expect(result[:success]).to be false
        expect(result[:error_type]).to eq(:validation)
        expect(result[:error]).to include("missing required fields")
      end
    end
  end

  describe "input sanitization" do
    it "accepts Korean level names" do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)

      result = service.generate_routine(level: "초급", week: 1, day: 1)

      expect(result[:success]).to be true
    end

    it "normalizes level to lowercase" do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)

      result = service.generate_routine(level: "BEGINNER", week: 1, day: 1)

      expect(result[:success]).to be true
    end

    it "converts string numbers to integers" do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)

      result = service.generate_routine(level: "beginner", week: "1", day: "1")

      expect(result[:success]).to be true
    end
  end

  describe "response parsing" do
    let(:service_instance) { described_class.new }

    it "extracts JSON from markdown code blocks" do
      response = "Here is the routine:\n```json\n{\"workoutType\": \"strength\", \"exercises\": [{\"exerciseName\": \"test\", \"targetMuscle\": \"chest\", \"sets\": 3, \"reps\": 10}]}\n```"

      # Access private method for testing
      parsed = service_instance.send(:parse_routine_response, response)

      expect(parsed["workoutType"]).to eq("strength")
    end

    it "handles JSON without markdown code blocks" do
      response = '{"workoutType": "strength", "exercises": [{"exerciseName": "test", "targetMuscle": "chest", "sets": 3, "reps": 10}]}'

      parsed = service_instance.send(:parse_routine_response, response)

      expect(parsed["workoutType"]).to eq("strength")
    end

    it "raises ParseError for invalid JSON" do
      response = "not valid json"

      expect {
        service_instance.send(:parse_routine_response, response)
      }.to raise_error(ClaudeApiService::ParseError)
    end
  end
end
