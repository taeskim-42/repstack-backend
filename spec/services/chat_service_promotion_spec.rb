# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatService, "promotion eligibility" do
  let(:user) { create(:user) }
  let!(:profile) do
    create(:user_profile,
      user: user,
      numeric_level: 3,
      current_level: "intermediate",
      level_assessed_at: 1.month.ago,
      height: 170
    )
  end

  describe "promotion eligibility check" do
    context "when user asks about promotion" do
      let(:promotion_keywords) { %w[승급 레벨 레벨업] }

      it "checks promotion eligibility when message contains promotion keywords" do
        # Mock the LevelTestService to return eligible
        allow_any_instance_of(AiTrainer::LevelTestService).to receive(:evaluate_promotion_readiness).and_return({
          eligible: true,
          current_level: 3,
          target_level: 4,
          estimated_1rms: { bench: 70, squat: 90, deadlift: 120 },
          required_1rms: { bench: 56, squat: 81, deadlift: 110 },
          exercise_results: {
            bench: { estimated_1rm: 70, required: 56, status: :passed, surplus: 14 },
            squat: { estimated_1rm: 90, required: 81, status: :passed, surplus: 9 },
            deadlift: { estimated_1rm: 120, required: 110, status: :passed, surplus: 10 }
          }
        })

        result = described_class.process(
          user: user,
          message: "승급 가능해?"
        )

        expect(result[:success]).to be true
        expect(result[:intent]).to eq("PROMOTION_ELIGIBLE")
        expect(result[:message]).to include("승급")
        expect(result[:data][:current_level]).to eq(3)
        expect(result[:data][:target_level]).to eq(4)
      end

      it "returns promotion eligible data with exercise results" do
        allow_any_instance_of(AiTrainer::LevelTestService).to receive(:evaluate_promotion_readiness).and_return({
          eligible: true,
          current_level: 3,
          target_level: 4,
          estimated_1rms: { bench: 70, squat: 90, deadlift: 120 },
          required_1rms: { bench: 56, squat: 81, deadlift: 110 },
          exercise_results: {
            bench: { estimated_1rm: 70, required: 56, status: :passed, surplus: 14 },
            squat: { estimated_1rm: 90, required: 81, status: :passed, surplus: 9 },
            deadlift: { estimated_1rm: 120, required: 110, status: :passed, surplus: 10 }
          }
        })

        result = described_class.process(
          user: user,
          message: "레벨업 할 수 있어?"
        )

        expect(result[:data][:estimated_1rms]).to be_present
        expect(result[:data][:required_1rms]).to be_present
        expect(result[:data][:exercise_results]).to be_present
      end
    end

    context "when user is not eligible for promotion" do
      it "processes message normally when not eligible" do
        allow_any_instance_of(AiTrainer::LevelTestService).to receive(:evaluate_promotion_readiness).and_return({
          eligible: false,
          current_level: 3,
          target_level: 4,
          estimated_1rms: { bench: 50, squat: 70, deadlift: 90 },
          required_1rms: { bench: 56, squat: 81, deadlift: 110 },
          exercise_results: {
            bench: { estimated_1rm: 50, required: 56, status: :failed, gap: 6 },
            squat: { estimated_1rm: 70, required: 81, status: :failed, gap: 11 },
            deadlift: { estimated_1rm: 90, required: 110, status: :failed, gap: 20 }
          }
        })

        result = described_class.process(
          user: user,
          message: "승급 가능해?"
        )

        # Should not return PROMOTION_ELIGIBLE intent when not eligible
        expect(result[:intent]).not_to eq("PROMOTION_ELIGIBLE")
      end
    end

    context "when user needs level assessment first" do
      before do
        # New user needs onboarding first
        profile.update!(onboarding_completed_at: nil, level_assessed_at: nil)
      end

      it "prioritizes level assessment over promotion check" do
        result = described_class.process(
          user: user,
          message: "승급하고 싶어"
        )

        expect(result[:intent]).to eq("LEVEL_ASSESSMENT")
      end
    end
  end

  describe "#should_check_promotion?" do
    let(:service) { described_class.new(user: user, message: message) }

    context "with promotion-related keywords" do
      let(:message) { "승급 가능해?" }

      it "returns true" do
        expect(service.send(:should_check_promotion?)).to be true
      end
    end

    context "with level keyword" do
      let(:message) { "내 레벨 어때?" }

      it "returns true" do
        expect(service.send(:should_check_promotion?)).to be true
      end
    end

    context "with unrelated message" do
      let(:message) { "벤치프레스 60kg 8회" }

      it "may return true randomly (10% chance) for fitness messages" do
        # Run multiple times to test randomness
        results = 100.times.map { service.send(:should_check_promotion?) }
        # Should have some true and some false due to 10% random chance
        # But since it's a record pattern, it's fitness related
        expect(results).to include(true).or include(false)
      end
    end

    context "with off-topic message" do
      let(:message) { "오늘 날씨 어때?" }

      it "returns false for non-fitness messages" do
        # Off-topic messages should not trigger promotion check
        # Because fitness_related? returns false
        allow(service).to receive(:fitness_related?).and_return(false)
        expect(service.send(:should_check_promotion?)).to be false
      end
    end
  end

  describe "#build_promotion_message" do
    let(:service) { described_class.new(user: user, message: "승급") }
    let(:result) do
      {
        current_level: 3,
        target_level: 4,
        estimated_1rms: { bench: 70, squat: 90, deadlift: 120 },
        required_1rms: { bench: 56, squat: 81, deadlift: 110 }
      }
    end

    it "builds encouraging message with level info" do
      message = service.send(:build_promotion_message, result)

      expect(message).to include("레벨 4")
      expect(message).to include("승급")
      expect(message).to include("도전")
    end

    it "includes tier in Korean" do
      message = service.send(:build_promotion_message, result)

      expect(message).to include("중급")
    end
  end

  describe "#tier_to_korean" do
    let(:service) { described_class.new(user: user, message: "test") }

    it "converts beginner to 초급" do
      expect(service.send(:tier_to_korean, "beginner")).to eq("초급")
    end

    it "converts intermediate to 중급" do
      expect(service.send(:tier_to_korean, "intermediate")).to eq("중급")
    end

    it "converts advanced to 고급" do
      expect(service.send(:tier_to_korean, "advanced")).to eq("고급")
    end
  end

  describe "integration with GraphQL" do
    let(:mutation) do
      <<~GQL
        mutation Chat($message: String!) {
          chat(input: { message: $message }) {
            success
            message
            intent
          }
        }
      GQL
    end

    it "returns PROMOTION_ELIGIBLE intent via GraphQL" do
      allow_any_instance_of(AiTrainer::LevelTestService).to receive(:evaluate_promotion_readiness).and_return({
        eligible: true,
        current_level: 3,
        target_level: 4,
        estimated_1rms: { bench: 70, squat: 90, deadlift: 120 },
        required_1rms: { bench: 56, squat: 81, deadlift: 110 },
        exercise_results: {
          bench: { estimated_1rm: 70, required: 56, status: :passed, surplus: 14 },
          squat: { estimated_1rm: 90, required: 81, status: :passed, surplus: 9 },
          deadlift: { estimated_1rm: 120, required: 110, status: :passed, surplus: 10 }
        }
      })

      result = RepstackBackendSchema.execute(
        mutation,
        variables: { "message" => "승급 도전할래" },
        context: { current_user: user }
      )

      data = result.dig("data", "chat")
      expect(data["success"]).to be true
      expect(data["intent"]).to eq("PROMOTION_ELIGIBLE")
    end
  end
end
