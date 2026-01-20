# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CheckConditionFromVoice, type: :graphql do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user) }

  let(:mutation) do
    <<~GRAPHQL
      mutation CheckConditionFromVoice($voiceText: String!) {
        checkConditionFromVoice(input: { voiceText: $voiceText }) {
          success
          condition {
            energyLevel
            stressLevel
            sleepQuality
            motivation
            soreness
            availableTime
            notes
          }
          adaptations
          intensityModifier
          durationModifier
          exerciseModifications
          restRecommendations
          interpretation
          error
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    context "with Korean voice input" do
      it "analyzes tired condition" do
        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "오늘 좀 피곤해요" },
          context: { current_user: user }
        )

        data = result["data"]["checkConditionFromVoice"]
        expect(data["success"]).to be true
        expect(data["condition"]["energyLevel"]).to be <= 3
        expect(data["adaptations"]).to include("운동 강도를 낮추세요")
        expect(data["error"]).to be_nil
      end

      it "analyzes good condition" do
        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "컨디션 좋아요, 운동하고 싶어요" },
          context: { current_user: user }
        )

        data = result["data"]["checkConditionFromVoice"]
        expect(data["success"]).to be true
        expect(data["condition"]["energyLevel"]).to be >= 3
        expect(data["condition"]["motivation"]).to be >= 3
      end

      it "analyzes soreness and modifies exercises" do
        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "어깨가 좀 아파요" },
          context: { current_user: user }
        )

        data = result["data"]["checkConditionFromVoice"]
        expect(data["success"]).to be true
        expect(data["condition"]["soreness"]).to include("shoulder")
        expect(data["exerciseModifications"]).to include("어깨 운동 제외")
      end
    end

    context "with English voice input" do
      it "analyzes tired condition" do
        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "I'm feeling tired today" },
          context: { current_user: user }
        )

        data = result["data"]["checkConditionFromVoice"]
        expect(data["success"]).to be true
        expect(data["condition"]["energyLevel"]).to be <= 3
      end

      it "analyzes great condition" do
        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "Feeling great and ready to workout!" },
          context: { current_user: user }
        )

        data = result["data"]["checkConditionFromVoice"]
        expect(data["success"]).to be true
        expect(data["condition"]["energyLevel"]).to be >= 3
      end
    end

    it "returns workout adaptations with modifiers" do
      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "오늘 피곤하고 스트레스 받았어요" },
        context: { current_user: user }
      )

      data = result["data"]["checkConditionFromVoice"]
      expect(data["success"]).to be true
      expect(data["adaptations"]).to be_an(Array)
      expect(data["adaptations"]).not_to be_empty
      expect(data["intensityModifier"]).to be_a(Float)
      expect(data["durationModifier"]).to be_a(Float)
    end

    it "saves condition log" do
      expect {
        execute_graphql(
          query: mutation,
          variables: { voiceText: "컨디션 괜찮아요" },
          context: { current_user: user }
        )
      }.to change(ConditionLog, :count).by(1)
    end

    it "returns interpretation" do
      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "오늘 좀 피곤해요" },
        context: { current_user: user }
      )

      data = result["data"]["checkConditionFromVoice"]
      expect(data["interpretation"]).to be_present
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "오늘 컨디션 좋아요" },
        context: { current_user: nil }
      )

      expect(result["errors"]).to be_present
    end
  end
end
