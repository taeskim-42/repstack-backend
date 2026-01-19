# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::MyRoutines, type: :graphql do
  let(:user) { create(:user) }

  let(:query) do
    <<~GRAPHQL
      query {
        myRoutines {
          id
          level
          weekNumber
          dayNumber
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    let!(:routine1) { create(:workout_routine, user: user, week_number: 1, day_number: 1) }
    let!(:routine2) { create(:workout_routine, user: user, week_number: 1, day_number: 2) }

    it "returns user routines" do
      result = execute_graphql(query: query, context: { current_user: user })

      data = result["data"]["myRoutines"]
      expect(data.length).to eq(2)
    end

    it "does not return other user's routines" do
      other_user = create(:user)
      create(:workout_routine, user: other_user)

      result = execute_graphql(query: query, context: { current_user: user })

      data = result["data"]["myRoutines"]
      expect(data.length).to eq(2)
    end
  end

  describe "when not authenticated" do
    it "returns nil or empty array" do
      result = execute_graphql(query: query, context: { current_user: nil })
      # Query returns nil for unauthenticated users
      expect(result["data"]["myRoutines"]).to be_nil.or(be_empty)
    end
  end
end
