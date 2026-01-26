# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::GetTrainerGreeting do
  let(:user) { create(:user, name: "홍길동") }

  describe "resolve" do
    context "when user has no profile (not onboarded)" do
      it "returns not ready response" do
        result = execute_query(user: user)

        expect(result["success"]).to be false
        expect(result["error"]).to include("온보딩")
      end
    end

    context "when user is on first day" do
      let!(:profile) do
        create(:user_profile,
               user: user,
               onboarding_completed_at: Time.current,
               numeric_level: 3,
               week_number: 1)
      end

      it "returns first day response with GENERATE_ROUTINE intent" do
        result = execute_query(user: user)

        expect(result["success"]).to be true
        expect(result["message"]).to include("홍길동")
        expect(result["message"]).to include("첫 운동")
        expect(result["intent"]).to eq("GENERATE_ROUTINE")
      end
    end

    context "when user is on day 2+ and already checked condition today" do
      let!(:profile) do
        create(:user_profile,
               user: user,
               onboarding_completed_at: 2.days.ago,
               numeric_level: 3,
               week_number: 1)
      end

      let!(:condition_log) do
        create(:condition_log, user: user, date: Date.current)
      end

      it "returns already checked response with GENERATE_ROUTINE intent" do
        result = execute_query(user: user)

        expect(result["success"]).to be true
        expect(result["message"]).to include("컨디션 체크는 완료")
        expect(result["intent"]).to eq("GENERATE_ROUTINE")
      end
    end

    context "when user is on day 2+ and has not checked condition today" do
      let!(:profile) do
        create(:user_profile,
               user: user,
               onboarding_completed_at: 2.days.ago,
               numeric_level: 3,
               week_number: 1)
      end

      it "returns greeting with CHECK_CONDITION intent" do
        result = execute_query(user: user)

        expect(result["success"]).to be true
        expect(result["message"]).to include("홍길동")
        expect(result["message"]).to include("컨디션은 어떠세요")
        expect(result["intent"]).to eq("CHECK_CONDITION")
      end

      it "includes day of week and fitness factor in message" do
        result = execute_query(user: user)

        # Should mention day and fitness factor
        expect(result["message"]).to match(/월요일|화요일|수요일|목요일|금요일|토요일|일요일/)
        expect(result["message"]).to match(/근력|근지구력|지속력|심폐지구력/)
      end

      it "includes current level info" do
        result = execute_query(user: user)

        expect(result["data"]["currentLevel"]).to eq(3)
      end
    end

    context "when unauthenticated" do
      it "returns error" do
        result = execute_query(user: nil)

        expect(result).to be_nil
      end
    end
  end

  def execute_query(user:)
    query = <<~GQL
      query {
        getTrainerGreeting {
          success
          message
          intent
          data {
            currentLevel
          }
          error
        }
      }
    GQL

    context = { current_user: user }
    result = RepstackBackendSchema.execute(query, context: context)

    if result["errors"]
      nil
    else
      result.dig("data", "getTrainerGreeting")
    end
  end
end
