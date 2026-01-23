# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiTrainer::LevelAssessmentService, type: :service do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, :needs_assessment, user: user) }

  describe "constants" do
    it "uses Haiku model for cost efficiency" do
      expect(described_class::MODEL).to eq("claude-3-5-haiku-20241022")
    end

    it "uses correct API URL" do
      expect(described_class::API_URL).to eq("https://api.anthropic.com/v1/messages")
    end
  end

  describe ".needs_assessment?" do
    context "when user has no profile" do
      let(:user_without_profile) { create(:user) }

      it "returns true" do
        expect(user_without_profile.user_profile).to be_nil
        expect(described_class.needs_assessment?(user_without_profile)).to be true
      end
    end

    context "when user has profile without level_assessed_at" do
      it "returns true" do
        expect(profile.level_assessed_at).to be_nil
        expect(described_class.needs_assessment?(user)).to be true
      end
    end

    context "when user has profile with level_assessed_at" do
      before { profile.update!(level_assessed_at: Time.current) }

      it "returns false" do
        expect(described_class.needs_assessment?(user)).to be false
      end
    end
  end

  describe ".assess" do
    context "in development mode without API key" do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it "returns mock response for initial state" do
        result = described_class.assess(user: user, message: "안녕하세요")

        expect(result[:success]).to be true
        expect(result[:message]).to be_present
        expect(result[:is_complete]).to be false
      end

      it "progresses through assessment states" do
        # First call - initial
        result1 = described_class.assess(user: user, message: "안녕")
        expect(result1[:is_complete]).to be false

        # Second call - asking experience
        result2 = described_class.assess(user: user, message: "1년 정도 했어요")
        expect(result2[:is_complete]).to be false

        # Third call - asking frequency
        result3 = described_class.assess(user: user, message: "주 3회")
        expect(result3[:is_complete]).to be false

        # Fourth call - complete
        result4 = described_class.assess(user: user, message: "근비대")
        expect(result4[:is_complete]).to be true
        expect(result4[:assessment]).to be_present
        expect(result4[:assessment]["experience_level"]).to eq "intermediate"
      end

      it "updates profile when assessment is complete" do
        # Progress to completion
        described_class.assess(user: user, message: "안녕")
        described_class.assess(user: user, message: "1년")
        described_class.assess(user: user, message: "주 3회")
        described_class.assess(user: user, message: "근비대")

        profile.reload
        expect(profile.level_assessed_at).to be_present
        expect(profile.numeric_level).to eq 3
        expect(profile.current_level).to eq "intermediate"
        expect(profile.fitness_goal).to eq "근비대"
      end
    end

    context "with API key configured" do
      let(:api_response) do
        {
          "content" => [
            {
              "text" => {
                "message" => "좋아요! 운동 경험이 어느 정도 되시나요?",
                "next_state" => "asking_experience",
                "collected_data" => {},
                "is_complete" => false,
                "assessment" => nil
              }.to_json
            }
          ]
        }
      end

      before do
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-key")
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          double(code: "200", body: api_response.to_json)
        )
      end

      it "calls Claude API and returns response" do
        result = described_class.assess(user: user, message: "안녕하세요")

        expect(result[:success]).to be true
        expect(result[:message]).to be_present
      end

      it "sends valid API request body with non-empty messages" do
        request_body = nil

        allow_any_instance_of(Net::HTTP).to receive(:request) do |_, req|
          request_body = JSON.parse(req.body)
          double(code: "200", body: api_response.to_json)
        end

        described_class.assess(user: user, message: "테스트 메시지")

        expect(request_body).to be_present
        expect(request_body["model"]).to eq("claude-3-5-haiku-20241022")
        expect(request_body["messages"]).to be_an(Array)

        # Verify all messages have non-empty content
        request_body["messages"].each do |msg|
          expect(msg["content"]).to be_present
          expect(msg["content"].strip).not_to be_empty
        end
      end
    end

    context "edge cases" do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it "handles empty user message gracefully" do
        result = described_class.assess(user: user, message: "")
        expect(result[:success]).to be true
      end

      it "handles whitespace-only message" do
        result = described_class.assess(user: user, message: "   ")
        expect(result[:success]).to be true
      end

      it "preserves assessment state across calls" do
        described_class.assess(user: user, message: "첫 번째 메시지")
        profile.reload

        state = profile.fitness_factors["assessment_state"]
        expect(state).to be_present
        expect(state).not_to eq("initial")
      end

      it "filters out empty content from conversation history" do
        # Simulate corrupted history with empty content
        profile.update!(
          fitness_factors: {
            "assessment_state" => "asking_experience",
            "collected_data" => {
              "conversation_history" => [
                { "role" => "user", "content" => "" },
                { "role" => "assistant", "content" => "valid message" }
              ]
            }
          }
        )

        # Should not raise error when building conversation
        result = described_class.assess(user: user, message: "새 메시지")
        expect(result[:success]).to be true
      end
    end
  end

  describe "integration with ChatService" do
    it "ChatService routes to LevelAssessmentService when level_assessed_at is nil" do
      expect(profile.level_assessed_at).to be_nil

      allow(described_class).to receive(:assess).and_return({
        success: true,
        message: "테스트 응답",
        is_complete: false,
        assessment: nil
      })

      result = ChatService.process(user: user, message: "안녕하세요")

      expect(described_class).to have_received(:assess)
      expect(result[:intent]).to eq("LEVEL_ASSESSMENT")
    end

    it "ChatService skips LevelAssessmentService when level_assessed_at is present" do
      profile.update!(level_assessed_at: Time.current)

      allow(described_class).to receive(:assess)

      # This should go to general chat, not level assessment
      ChatService.process(user: user, message: "안녕하세요")

      expect(described_class).not_to have_received(:assess)
    end
  end
end
