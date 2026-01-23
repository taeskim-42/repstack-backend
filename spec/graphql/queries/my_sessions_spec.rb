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

  let(:detailed_query) do
    <<~GRAPHQL
      query MySessions {
        mySessions(limit: 10, includeSets: true) {
          id
          name
          status
          startTime
          endTime
          totalVolume
          totalSets
          exercisesPerformed
          durationInSeconds
          durationFormatted
          active
          completed
          createdAt
          updatedAt
          workoutSets {
            id
            exerciseName
            setNumber
            weight
            weightUnit
            reps
            durationSeconds
            rpe
            notes
            volume
            isTimedExercise
            isWeightedExercise
            durationFormatted
            weightInKg
            weightInLbs
            createdAt
            updatedAt
          }
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

    context 'with workout sets' do
      let!(:workout_set) do
        create(:workout_set, workout_session: session1,
               exercise_name: '벤치프레스', weight: 60, reps: 10, set_number: 1)
      end

      it 'returns workout sets with all fields' do
        result = execute_graphql(query: detailed_query, context: { current_user: user })

        sessions = result['data']['mySessions']
        session_with_sets = sessions.find { |s| s['workoutSets'].any? }
        expect(session_with_sets).to be_present

        set = session_with_sets['workoutSets'].first
        expect(set['exerciseName']).to eq('벤치프레스')
        expect(set['weight']).to eq(60.0)
        expect(set['reps']).to eq(10)
        expect(set['volume']).to be_present
        expect(set['createdAt']).to match(/^\d{4}-\d{2}-\d{2}/)
        expect(set['updatedAt']).to match(/^\d{4}-\d{2}-\d{2}/)
      end

      it 'returns session computed fields' do
        result = execute_graphql(query: detailed_query, context: { current_user: user })

        session = result['data']['mySessions'].find { |s| s['id'] == session1.id.to_s }
        expect(session['totalVolume']).to be >= 0
        expect(session['totalSets']).to be >= 1
        expect(session['createdAt']).to match(/^\d{4}-\d{2}-\d{2}/)
      end
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = execute_graphql(query: query, context: { current_user: nil })
      expect(result["errors"]).to be_present
      expect(result["errors"].first["message"]).to include("sign in")
    end
  end
end
