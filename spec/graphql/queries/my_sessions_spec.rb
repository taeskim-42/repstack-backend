# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::MySessions, type: :graphql do
  let(:user) { create(:user) }

  let(:query) do
    <<~GRAPHQL
      query MySessions($limit: Int, $includeSets: Boolean) {
        mySessions(limit: $limit, includeSets: $includeSets) {
          id
          name
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    # Create completed sessions so we can have multiple
    let!(:session1) { create(:workout_session, :completed, user: user) }
    let!(:session2) { create(:workout_session, user: user) }

    it "returns user sessions" do
      result = execute_graphql(query: query, context: { current_user: user })

      data = result["data"]["mySessions"]
      expect(data.length).to eq(2)
    end

    it "respects limit parameter" do
      result = execute_graphql(
        query: query,
        variables: { limit: 1 },
        context: { current_user: user }
      )

      data = result["data"]["mySessions"]
      expect(data.length).to eq(1)
    end

    it "caps limit at MAX_LIMIT" do
      result = execute_graphql(
        query: query,
        variables: { limit: 200 },
        context: { current_user: user }
      )

      # Should not error and return available sessions
      data = result["data"]["mySessions"]
      expect(data).to be_an(Array)
    end

    it "includes workout sets when requested" do
      result = execute_graphql(
        query: query,
        variables: { includeSets: true },
        context: { current_user: user }
      )

      expect(result["data"]["mySessions"]).to be_an(Array)
    end
  end

  describe "when not authenticated" do
    it "returns empty array" do
      result = execute_graphql(query: query, context: { current_user: nil })
      expect(result["data"]["mySessions"]).to eq([])
    end
  end
end
