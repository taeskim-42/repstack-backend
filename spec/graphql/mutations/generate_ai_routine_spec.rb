# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::GenerateAiRoutine, type: :graphql do
  let(:user) { create(:user, :with_profile) }

  let(:mutation) do
    <<~GRAPHQL
      mutation GenerateAiRoutine($input: GenerateAiRoutineInput!) {
        generateAiRoutine(input: $input) {
          success
          routine {
            routineId
            dayOfWeek
            dayKorean
            tier
            userLevel
            estimatedDurationMinutes
            exercises {
              exerciseId
              exerciseName
              sets
              reps
              targetMuscle
            }
          }
          error
        }
      }
    GRAPHQL
  end

  let(:mock_routine) do
    {
      routine_id: "routine-123",
      day_of_week: "MONDAY",
      day_korean: "월요일",
      tier: "intermediate",
      user_level: 3,
      estimated_duration_minutes: 45,
      exercises: [
        { exercise_id: "EX_CH01", exercise_name: "벤치프레스", sets: 4, reps: 8, target_muscle: "CHEST" },
        { exercise_id: "EX_CH02", exercise_name: "인클라인 덤벨프레스", sets: 3, reps: 10, target_muscle: "CHEST" }
      ],
      condition: { energy_level: 3, stress_level: 2 },
      fitness_factor: "normal",
      fitness_factor_korean: "일반",
      generated_at: Time.current.iso8601
    }
  end

  describe "when authenticated" do
    context "with no parameters" do
      before do
        allow(AiTrainer).to receive(:generate_routine).and_return(mock_routine)
      end

      it "generates routine successfully" do
        result = RepstackBackendSchema.execute(
          mutation,
          variables: { input: {} },
          context: { current_user: user }
        )
        data = result["data"]["generateAiRoutine"]

        expect(data["success"]).to be true
        expect(data["routine"]).to be_present
        expect(data["error"]).to be_nil
      end

      it "returns routine details" do
        result = RepstackBackendSchema.execute(
          mutation,
          variables: { input: {} },
          context: { current_user: user }
        )
        data = result["data"]["generateAiRoutine"]

        expect(data["routine"]["routineId"]).to eq("routine-123")
        expect(data["routine"]["tier"]).to eq("intermediate")
        expect(data["routine"]["estimatedDurationMinutes"]).to eq(45)
      end

      it "returns exercise details" do
        result = RepstackBackendSchema.execute(
          mutation,
          variables: { input: {} },
          context: { current_user: user }
        )
        data = result["data"]["generateAiRoutine"]

        exercises = data["routine"]["exercises"]
        expect(exercises).to be_an(Array)
        expect(exercises.first["exerciseName"]).to eq("벤치프레스")
      end
    end

    context "with day_of_week parameter" do
      before do
        allow(AiTrainer).to receive(:generate_routine).and_return(mock_routine)
      end

      it "passes day_of_week to service" do
        expect(AiTrainer).to receive(:generate_routine).with(
          hash_including(day_of_week: 3)
        ).and_return(mock_routine)

        RepstackBackendSchema.execute(
          mutation,
          variables: { input: { dayOfWeek: 3 } },
          context: { current_user: user }
        )
      end
    end

    context "with condition input" do
      let(:condition_input) do
        {
          energyLevel: 4,
          stressLevel: 2,
          sleepQuality: 5,
          motivation: 5,
          availableTime: 60
        }
      end

      before do
        allow(AiTrainer).to receive(:generate_routine).and_return(mock_routine)
      end

      it "passes condition to service" do
        expect(AiTrainer).to receive(:generate_routine).with(
          hash_including(condition_inputs: hash_including(energy_level: 4, stress_level: 2))
        ).and_return(mock_routine)

        RepstackBackendSchema.execute(
          mutation,
          variables: { input: { condition: condition_input } },
          context: { current_user: user }
        )
      end

      it "generates routine adjusted for condition" do
        result = RepstackBackendSchema.execute(
          mutation,
          variables: { input: { condition: condition_input } },
          context: { current_user: user }
        )
        data = result["data"]["generateAiRoutine"]

        expect(data["success"]).to be true
      end
    end

    context "when service returns error" do
      before do
        allow(AiTrainer).to receive(:generate_routine).and_return({
          success: false,
          error: "AI 서비스를 일시적으로 사용할 수 없습니다."
        })
      end

      it "returns error response" do
        result = RepstackBackendSchema.execute(
          mutation,
          variables: { input: {} },
          context: { current_user: user }
        )
        data = result["data"]["generateAiRoutine"]

        expect(data["success"]).to be false
        expect(data["routine"]).to be_nil
        expect(data["error"]).to eq("AI 서비스를 일시적으로 사용할 수 없습니다.")
      end
    end

    context "when user has recent feedbacks" do
      let!(:feedbacks) { create_list(:workout_feedback, 3, user: user) }

      before do
        allow(AiTrainer).to receive(:generate_routine).and_return(mock_routine)
      end

      it "includes recent feedbacks in service call" do
        expect(AiTrainer).to receive(:generate_routine).with(
          hash_including(:recent_feedbacks)
        ).and_return(mock_routine)

        RepstackBackendSchema.execute(
          mutation,
          variables: { input: {} },
          context: { current_user: user }
        )
      end
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = RepstackBackendSchema.execute(
        mutation,
        variables: { input: {} },
        context: { current_user: nil }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["message"]).to eq("Authentication required")
    end
  end
end
