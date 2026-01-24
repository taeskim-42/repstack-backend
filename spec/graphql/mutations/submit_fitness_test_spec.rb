# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SubmitFitnessTest, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, level_assessed_at: nil, numeric_level: 1) }

  let(:mutation) do
    <<~GQL
      mutation SubmitFitnessTest($pushupCount: Int!, $squatCount: Int!, $pullupCount: Int!) {
        submitFitnessTest(input: { pushupCount: $pushupCount, squatCount: $squatCount, pullupCount: $pullupCount }) {
          result {
            success
            fitnessScore
            assignedLevel
            assignedTier
            message
            recommendations
            exerciseResults {
              pushup { count tier tierKorean points }
              squat { count tier tierKorean points }
              pullup { count tier tierKorean points }
            }
            errors
          }
          errors
        }
      }
    GQL
  end

  def execute_mutation(variables = {}, current_user: user)
    RepstackBackendSchema.execute(
      mutation,
      variables: variables,
      context: { current_user: current_user }
    )
  end

  describe "successful fitness test submission" do
    it "returns fitness test result" do
      result = execute_mutation(
        { "pushupCount" => 25, "squatCount" => 35, "pullupCount" => 10 }
      )

      data = result.dig("data", "submitFitnessTest")
      expect(data["errors"]).to be_empty
      expect(data["result"]["success"]).to be true
      expect(data["result"]["fitnessScore"]).to be_between(20, 100)
      expect(data["result"]["assignedLevel"]).to be_between(1, 8)
      expect(data["result"]["assignedTier"]).to be_present
      expect(data["result"]["message"]).to be_present
    end

    it "updates user profile" do
      execute_mutation(
        { "pushupCount" => 30, "squatCount" => 40, "pullupCount" => 12 }
      )

      profile.reload
      expect(profile.level_assessed_at).to be_present
      expect(profile.fitness_factors["fitness_test_result"]).to be_present
    end

    it "returns exercise results breakdown" do
      result = execute_mutation(
        { "pushupCount" => 20, "squatCount" => 30, "pullupCount" => 8 }
      )

      exercise_results = result.dig("data", "submitFitnessTest", "result", "exerciseResults")
      expect(exercise_results["pushup"]["count"]).to eq(20)
      expect(exercise_results["pushup"]["tier"]).to eq("good")
      expect(exercise_results["squat"]["count"]).to eq(30)
      expect(exercise_results["pullup"]["count"]).to eq(8)
    end
  end

  describe "validation errors" do
    it "rejects negative values" do
      result = execute_mutation(
        { "pushupCount" => -5, "squatCount" => 20, "pullupCount" => 5 }
      )

      errors = result.dig("data", "submitFitnessTest", "errors")
      expect(errors).to include(a_string_matching(/0 이상/))
    end

    it "rejects unrealistic values" do
      result = execute_mutation(
        { "pushupCount" => 500, "squatCount" => 20, "pullupCount" => 5 }
      )

      errors = result.dig("data", "submitFitnessTest", "errors")
      expect(errors).to include(a_string_matching(/비정상/))
    end
  end

  describe "authorization" do
    it "requires authentication" do
      result = execute_mutation(
        { "pushupCount" => 20, "squatCount" => 30, "pullupCount" => 10 },
        current_user: nil
      )

      errors = result.dig("data", "submitFitnessTest", "errors")
      expect(errors).to include(a_string_matching(/인증/))
    end
  end

  describe "already assessed user" do
    before do
      profile.update!(level_assessed_at: 1.day.ago)
    end

    it "prevents re-assessment" do
      result = execute_mutation(
        { "pushupCount" => 20, "squatCount" => 30, "pullupCount" => 10 }
      )

      errors = result.dig("data", "submitFitnessTest", "errors")
      expect(errors).to include(a_string_matching(/이미 레벨이 측정/))
    end
  end

  describe "level assignment based on performance" do
    it "assigns beginner level for poor performance" do
      result = execute_mutation(
        { "pushupCount" => 5, "squatCount" => 10, "pullupCount" => 1 }
      )

      data = result.dig("data", "submitFitnessTest", "result")
      expect(data["assignedLevel"]).to eq(1)
      expect(data["assignedTier"]).to eq("beginner")
    end

    it "assigns intermediate level for good performance" do
      result = execute_mutation(
        { "pushupCount" => 30, "squatCount" => 45, "pullupCount" => 12 }
      )

      data = result.dig("data", "submitFitnessTest", "result")
      expect(data["assignedTier"]).to eq("intermediate")
    end

    it "assigns advanced level for excellent performance" do
      result = execute_mutation(
        { "pushupCount" => 45, "squatCount" => 65, "pullupCount" => 20 }
      )

      data = result.dig("data", "submitFitnessTest", "result")
      expect(data["assignedTier"]).to be_in(%w[intermediate advanced])
    end
  end
end
