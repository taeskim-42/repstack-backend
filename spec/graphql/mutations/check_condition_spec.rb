# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CheckCondition, type: :graphql do
  let(:user) { create(:user, :with_profile) }

  let(:mutation) do
    <<~GRAPHQL
      mutation CheckCondition($input: CheckConditionInput!) {
        checkCondition(input: $input) {
          success
          adaptations
          intensityModifier
          durationModifier
          exerciseModifications
          restRecommendations
          error
        }
      }
    GRAPHQL
  end

  let(:condition_data) do
    {
      energyLevel: 3,
      stressLevel: 2,
      sleepQuality: 4,
      motivation: 4,
      availableTime: 60,
      soreness: { "legs" => 3 },
      notes: "어제 하체 운동을 했습니다."
    }
  end

  describe "when authenticated" do
    context "with valid condition input" do
      before do
        allow(AiTrainer::ConditionService).to receive(:analyze_from_input).and_return({
          success: true,
          adaptations: ["오늘은 하체 운동 강도를 줄이세요."],
          intensity_modifier: 0.8,
          duration_modifier: 1.0,
          exercise_modifications: ["스쿼트 대신 레그프레스 권장"],
          rest_recommendations: ["세트 간 휴식 시간 30초 증가"]
        })
      end

      it "checks condition successfully" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["success"]).to be true
        expect(data["error"]).to be_nil
      end

      it "returns adaptations" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["adaptations"]).to include("오늘은 하체 운동 강도를 줄이세요.")
      end

      it "returns intensity modifier" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["intensityModifier"]).to eq(0.8)
      end

      it "returns duration modifier" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["durationModifier"]).to eq(1.0)
      end

      it "returns exercise modifications" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["exerciseModifications"]).to include("스쿼트 대신 레그프레스 권장")
      end

      it "returns rest recommendations" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["restRecommendations"]).to include("세트 간 휴식 시간 30초 증가")
      end

      it "saves condition log" do
        expect {
          execute_graphql(
            query: mutation,
            variables: { input: { input: condition_data } },
            context: { current_user: user }
          )
        }.to change(ConditionLog, :count).by(1)
      end

      it "saves correct condition values" do
        execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )

        log = ConditionLog.last
        expect(log.user).to eq(user)
        expect(log.energy_level).to eq(3)
        expect(log.stress_level).to eq(2)
        expect(log.sleep_quality).to eq(4)
        expect(log.motivation).to eq(4)
        expect(log.available_time).to eq(60)
      end
    end

    context "with high energy condition" do
      let(:high_energy_data) do
        {
          energyLevel: 5,
          stressLevel: 1,
          sleepQuality: 5,
          motivation: 5,
          availableTime: 90
        }
      end

      before do
        allow(AiTrainer::ConditionService).to receive(:analyze_from_input).and_return({
          success: true,
          adaptations: ["컨디션이 좋습니다! 오늘은 강도 높은 운동이 가능합니다."],
          intensity_modifier: 1.1,
          duration_modifier: 1.2,
          exercise_modifications: [],
          rest_recommendations: []
        })
      end

      it "returns higher intensity modifier" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: high_energy_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["intensityModifier"]).to be > 1.0
      end
    end

    context "with low energy condition" do
      let(:low_energy_data) do
        {
          energyLevel: 1,
          stressLevel: 5,
          sleepQuality: 1,
          motivation: 2,
          availableTime: 30
        }
      end

      before do
        allow(AiTrainer::ConditionService).to receive(:analyze_from_input).and_return({
          success: true,
          adaptations: ["오늘은 휴식이 필요해 보입니다.", "가벼운 스트레칭만 권장합니다."],
          intensity_modifier: 0.5,
          duration_modifier: 0.5,
          exercise_modifications: ["고중량 운동 피하기", "유산소 운동으로 대체"],
          rest_recommendations: ["충분한 수면 권장", "스트레스 관리 필요"]
        })
      end

      it "returns lower intensity modifier" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: low_energy_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["intensityModifier"]).to be < 1.0
      end

      it "returns multiple adaptations" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: low_energy_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["adaptations"].length).to be >= 2
      end
    end

    context "without optional fields" do
      let(:minimal_data) do
        {
          energyLevel: 3,
          stressLevel: 3,
          sleepQuality: 3,
          motivation: 3,
          availableTime: 45
        }
      end

      before do
        allow(AiTrainer::ConditionService).to receive(:analyze_from_input).and_return({
          success: true,
          adaptations: [],
          intensity_modifier: 1.0,
          duration_modifier: 1.0,
          exercise_modifications: [],
          rest_recommendations: []
        })
      end

      it "works without soreness" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: minimal_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["success"]).to be true
      end

      it "works without notes" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: minimal_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["success"]).to be true
      end
    end

    context "when service returns error" do
      before do
        allow(AiTrainer::ConditionService).to receive(:analyze_from_input).and_return({
          success: false,
          error: "AI 서비스 오류"
        })
      end

      it "returns error response" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["success"]).to be false
        expect(data["error"]).to eq("AI 서비스 오류")
      end

      it "returns nil for all other fields" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["adaptations"]).to be_nil
        expect(data["intensityModifier"]).to be_nil
        expect(data["durationModifier"]).to be_nil
      end
    end

    context "when condition log save fails" do
      before do
        allow(AiTrainer::ConditionService).to receive(:analyze_from_input).and_return({
          success: true,
          adaptations: [],
          intensity_modifier: 1.0,
          duration_modifier: 1.0,
          exercise_modifications: [],
          rest_recommendations: []
        })
        allow(ConditionLog).to receive(:create!).and_raise(StandardError, "DB error")
      end

      it "still returns success (log save is not critical)" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: condition_data } },
          context: { current_user: user }
        )
        data = response["data"]["checkCondition"]

        expect(data["success"]).to be true
      end
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      response = execute_graphql(
        query: mutation,
        variables: { input: { input: condition_data } },
        context: { current_user: nil }
      )

      expect(response["errors"]).to be_present
      expect(response["errors"].first["message"]).to eq("Authentication required")
    end
  end
end
