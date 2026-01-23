# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::StartLevelTest, type: :graphql do
  let(:user) { create(:user, :with_profile) }

  let(:mutation) do
    <<~GRAPHQL
      mutation StartLevelTest {
        startLevelTest(input: {}) {
          success
          test {
            testId
            testType
            currentLevel
            targetLevel
            timeLimitMinutes
            instructions
            exercises {
              exerciseName
              exerciseType
              targetWeightKg
              targetReps
            }
          }
          error
        }
      }
    GRAPHQL
  end

  let(:mock_test) do
    {
      test_id: "test-123",
      test_type: "level_up",
      current_level: 2,
      target_level: 3,
      time_limit_minutes: 30,
      instructions: ["각 운동을 올바른 자세로 수행하세요."],
      exercises: [
        { exercise_name: "스쿼트", exercise_type: "squat", target_weight_kg: 80.0, target_reps: 5, order: 1, rest_minutes: 3 },
        { exercise_name: "데드리프트", exercise_type: "deadlift", target_weight_kg: 100.0, target_reps: 5, order: 2, rest_minutes: 3 }
      ],
      criteria: { min_reps: 5, max_rpe: 8 },
      pass_conditions: { all_exercises_completed: true, within_time_limit: true }
    }
  end

  describe "when authenticated" do
    context "when user is eligible for level test" do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: true,
          reason: nil
        })
        allow(AiTrainer).to receive(:generate_level_test).and_return(mock_test)
      end

      it "starts level test successfully" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        expect(data["success"]).to be true
        expect(data["test"]).to be_present
        expect(data["error"]).to be_nil
      end

      it "returns test details" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        expect(data["test"]["testId"]).to eq("test-123")
        expect(data["test"]["testType"]).to eq("level_up")
        expect(data["test"]["timeLimitMinutes"]).to eq(30)
      end

      it "returns exercise details" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        exercises = data["test"]["exercises"]
        expect(exercises).to be_an(Array)
        expect(exercises.first["exerciseName"]).to eq("스쿼트")
        expect(exercises.first["targetWeightKg"]).to eq(80.0)
      end

      it "returns instructions" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        expect(data["test"]["instructions"]).to include("각 운동을 올바른 자세로 수행하세요.")
      end
    end

    context "when user is not eligible for level test" do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: false,
          reason: "이미 최고 레벨입니다."
        })
      end

      it "returns error" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        expect(data["success"]).to be false
        expect(data["test"]).to be_nil
        expect(data["error"]).to eq("이미 최고 레벨입니다.")
      end
    end

    context "when eligibility check returns need more workouts" do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: false,
          reason: "레벨 테스트를 위해 최소 5회 이상의 운동 기록이 필요합니다."
        })
      end

      it "returns appropriate error message" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        expect(data["success"]).to be false
        expect(data["error"]).to include("5회")
      end
    end

    context "when test generation fails" do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: true,
          reason: nil
        })
        allow(AiTrainer).to receive(:generate_level_test).and_return({
          success: false,
          error: "AI 서비스 오류가 발생했습니다."
        })
      end

      it "returns error" do
        result = RepstackBackendSchema.execute(mutation, context: { current_user: user })
        data = result["data"]["startLevelTest"]

        expect(data["success"]).to be false
        expect(data["test"]).to be_nil
        expect(data["error"]).to eq("AI 서비스 오류가 발생했습니다.")
      end
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = RepstackBackendSchema.execute(mutation, context: { current_user: nil })

      expect(result["errors"]).to be_present
      expect(result["errors"].first["message"]).to eq("Authentication required")
    end
  end
end
