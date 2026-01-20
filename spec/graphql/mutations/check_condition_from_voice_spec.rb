# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CheckConditionFromVoice, type: :graphql do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user) }

  # Mock AiTrainerService responses
  let(:tired_condition_response) do
    {
      success: true,
      condition: {
        energy_level: 2,
        stress_level: 3,
        sleep_quality: 3,
        motivation: 3,
        soreness: {},
        available_time: 60,
        notes: "피곤함"
      },
      adaptations: ["운동 강도를 낮추세요", "휴식 시간을 늘리세요"],
      intensity_modifier: 0.7,
      duration_modifier: 0.8,
      exercise_modifications: [],
      rest_recommendations: ["충분한 수분 섭취"],
      interpretation: "피곤한 상태로 보입니다."
    }
  end

  let(:good_condition_response) do
    {
      success: true,
      condition: {
        energy_level: 4,
        stress_level: 2,
        sleep_quality: 4,
        motivation: 5,
        soreness: {},
        available_time: 90,
        notes: "좋은 컨디션"
      },
      adaptations: ["정상 강도로 운동하세요"],
      intensity_modifier: 1.0,
      duration_modifier: 1.0,
      exercise_modifications: [],
      rest_recommendations: [],
      interpretation: "컨디션이 좋습니다."
    }
  end

  let(:soreness_condition_response) do
    {
      success: true,
      condition: {
        energy_level: 3,
        stress_level: 3,
        sleep_quality: 3,
        motivation: 3,
        soreness: { "shoulder" => 3 },
        available_time: 60,
        notes: "어깨 통증"
      },
      adaptations: ["어깨 운동을 피하세요"],
      intensity_modifier: 0.8,
      duration_modifier: 0.9,
      exercise_modifications: ["어깨 운동 제외"],
      rest_recommendations: ["어깨 스트레칭"],
      interpretation: "어깨 통증이 있습니다."
    }
  end

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
        allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(tired_condition_response)

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
        allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(good_condition_response)

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
        allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(soreness_condition_response)

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
        allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(tired_condition_response)

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
        allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(good_condition_response)

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
      allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(tired_condition_response)

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
      allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(good_condition_response)

      expect {
        execute_graphql(
          query: mutation,
          variables: { voiceText: "컨디션 괜찮아요" },
          context: { current_user: user }
        )
      }.to change(ConditionLog, :count).by(1)
    end

    it "returns interpretation" do
      allow(AiTrainerService).to receive(:check_condition_from_voice).and_return(tired_condition_response)

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
