# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::TodayRoutine, type: :graphql do
  let(:user) { create(:user) }
  let(:profile) { user.user_profile || user.create_user_profile! }

  let(:query) do
    <<~GRAPHQL
      query {
        todayRoutine {
          id
          level
          weekNumber
          dayNumber
          dayOfWeek
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    before do
      # Ensure user has a profile
      profile
    end

    context "with matching routine" do
      let!(:routine) do
        current_day = Date.current.strftime("%A")
        create(:workout_routine,
               user: user,
               level: profile.current_level,
               week_number: profile.week_number,
               day_number: profile.day_number,
               day_of_week: current_day,
               is_completed: false)
      end

      it "returns today's routine" do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result["data"]["todayRoutine"]
        expect(data).to be_present
        expect(data["id"]).to eq(routine.id.to_s)
        expect(data["level"]).to eq(profile.current_level)
      end
    end

    context "without matching routine" do
      it "returns nil" do
        result = execute_graphql(query: query, context: { current_user: user })
        expect(result["data"]["todayRoutine"]).to be_nil
      end
    end

    context "with completed routine" do
      let!(:routine) do
        current_day = Date.current.strftime("%A")
        create(:workout_routine,
               user: user,
               level: profile.current_level,
               week_number: profile.week_number,
               day_number: profile.day_number,
               day_of_week: current_day,
               is_completed: true,
               completed_at: Time.current)
      end

      it "returns nil" do
        result = execute_graphql(query: query, context: { current_user: user })
        expect(result["data"]["todayRoutine"]).to be_nil
      end
    end
  end

  describe "when not authenticated" do
    it "returns nil" do
      result = execute_graphql(query: query, context: { current_user: nil })
      expect(result["data"]["todayRoutine"]).to be_nil
    end
  end
end
