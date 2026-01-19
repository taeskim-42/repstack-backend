# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout Mutations", type: :graphql do
  let(:user) { create(:user, :with_profile) }

  describe Mutations::StartWorkoutSession do
    let(:mutation) do
      <<~GRAPHQL
        mutation StartWorkoutSession($name: String) {
          startWorkoutSession(input: { name: $name }) {
            workoutSession {
              id
              name
              active
            }
            errors
          }
        }
      GRAPHQL
    end

    context "when authenticated" do
      it "creates a new workout session" do
        response = execute_graphql_as(user, query: mutation, variables: { name: "Morning Workout" })
        data = graphql_data(response)["startWorkoutSession"]

        expect(data["errors"]).to be_empty
        expect(data["workoutSession"]["name"]).to eq("Morning Workout")
        expect(data["workoutSession"]["active"]).to be true
      end

      it "prevents creating multiple active sessions" do
        create(:workout_session, :active, user: user)

        response = execute_graphql_as(user, query: mutation, variables: { name: "Another Workout" })
        data = graphql_data(response)["startWorkoutSession"]

        expect(data["workoutSession"]).to be_nil
        expect(data["errors"]).to include(match(/already have an active/i))
      end
    end

    context "when not authenticated" do
      it "returns authentication error" do
        response = execute_graphql(query: mutation, variables: { name: "Test" })

        expect(graphql_errors(response)).to be_present
      end
    end
  end

  describe Mutations::EndWorkoutSession do
    let(:mutation) do
      <<~GRAPHQL
        mutation EndWorkoutSession($id: ID!) {
          endWorkoutSession(input: { id: $id }) {
            workoutSession {
              id
              active
              completed
            }
            errors
          }
        }
      GRAPHQL
    end

    let!(:session) { create(:workout_session, :active, user: user) }

    it "completes an active session" do
      response = execute_graphql_as(user, query: mutation, variables: { id: session.id.to_s })
      data = graphql_data(response)["endWorkoutSession"]

      expect(data["errors"]).to be_empty
      expect(data["workoutSession"]["active"]).to be false
      expect(data["workoutSession"]["completed"]).to be true
    end

    it "prevents ending already completed session" do
      session.complete!

      response = execute_graphql_as(user, query: mutation, variables: { id: session.id.to_s })
      data = graphql_data(response)["endWorkoutSession"]

      expect(data["workoutSession"]).to be_nil
      expect(data["errors"]).to include(match(/already completed/i))
    end

    it "prevents ending another user's session" do
      other_user = create(:user)
      other_session = create(:workout_session, :active, user: other_user)

      response = execute_graphql_as(user, query: mutation, variables: { id: other_session.id.to_s })
      data = graphql_data(response)["endWorkoutSession"]

      expect(data["workoutSession"]).to be_nil
      expect(data["errors"]).to include(match(/not found/i))
    end
  end

  describe Mutations::AddWorkoutSet do
    let(:mutation) do
      <<~GRAPHQL
        mutation AddWorkoutSet($sessionId: ID!, $exerciseName: String!, $weight: Float, $reps: Int) {
          addWorkoutSet(input: { sessionId: $sessionId, exerciseName: $exerciseName, weight: $weight, reps: $reps }) {
            workoutSet {
              id
              exerciseName
              weight
              reps
            }
            errors
          }
        }
      GRAPHQL
    end

    let!(:session) { create(:workout_session, :active, user: user) }

    it "adds a set to active session" do
      response = execute_graphql_as(
        user,
        query: mutation,
        variables: { sessionId: session.id.to_s, exerciseName: "Bench Press", weight: 60.0, reps: 10 }
      )
      data = graphql_data(response)["addWorkoutSet"]

      expect(data["errors"]).to be_empty
      expect(data["workoutSet"]["exerciseName"]).to eq("Bench Press")
      expect(data["workoutSet"]["weight"]).to eq(60.0)
    end

    it "prevents adding to completed session" do
      session.complete!

      response = execute_graphql_as(
        user,
        query: mutation,
        variables: { sessionId: session.id.to_s, exerciseName: "Squat", reps: 10 }
      )
      data = graphql_data(response)["addWorkoutSet"]

      expect(data["workoutSet"]).to be_nil
      expect(data["errors"]).to include(match(/not active/i))
    end

    it "validates weight unit" do
      response = execute_graphql_as(
        user,
        query: <<~GRAPHQL,
          mutation {
            addWorkoutSet(input: { sessionId: "#{session.id}", exerciseName: "Test", weightUnit: "invalid" }) {
              errors
            }
          }
        GRAPHQL
        variables: {}
      )

      expect(graphql_errors(response)).to be_present
    end
  end
end
