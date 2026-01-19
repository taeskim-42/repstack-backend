# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::MyProfile, type: :graphql do
  let(:user) { create(:user) }

  let(:query) do
    <<~GRAPHQL
      query {
        myProfile {
          id
          currentLevel
          weekNumber
          dayNumber
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    context "with profile" do
      before do
        # Ensure user has a profile
        user.user_profile || user.create_user_profile!
      end

      it "returns user profile" do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result["data"]["myProfile"]
        expect(data).to be_present
        expect(data["currentLevel"]).to eq("beginner")
        expect(data["weekNumber"]).to eq(1)
        expect(data["dayNumber"]).to eq(1)
      end
    end

    context "without profile" do
      before do
        user.user_profile&.destroy
      end

      it "returns nil" do
        result = execute_graphql(query: query, context: { current_user: user.reload })
        expect(result["data"]["myProfile"]).to be_nil
      end
    end
  end

  describe "when not authenticated" do
    it "returns nil" do
      result = execute_graphql(query: query, context: { current_user: nil })
      expect(result["data"]["myProfile"]).to be_nil
    end
  end
end
