# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CompleteRoutine, type: :graphql do
  let(:user) { create(:user) }
  let(:routine) { create(:workout_routine, user: user, is_completed: false) }

  let(:mutation) do
    <<~GRAPHQL
      mutation CompleteRoutine($routineId: ID!) {
        completeRoutine(input: { routineId: $routineId }) {
          workoutRoutine {
            id
            isCompleted
          }
          userProfile {
            dayNumber
          }
          errors
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    it "marks routine as completed" do
      result = execute_graphql(
        query: mutation,
        variables: { routineId: routine.id.to_s },
        context: { current_user: user }
      )

      data = result["data"]["completeRoutine"]
      expect(data["errors"]).to be_empty
      expect(data["workoutRoutine"]["isCompleted"]).to be true
    end

    it "returns error for non-existent routine" do
      result = execute_graphql(
        query: mutation,
        variables: { routineId: "999999" },
        context: { current_user: user }
      )

      data = result["data"]["completeRoutine"]
      expect(data["errors"]).to include("Routine not found")
    end

    it "returns error for already completed routine" do
      routine.update!(is_completed: true, completed_at: Time.current)

      result = execute_graphql(
        query: mutation,
        variables: { routineId: routine.id.to_s },
        context: { current_user: user }
      )

      data = result["data"]["completeRoutine"]
      expect(data["errors"]).to include("Routine is already completed")
    end

    it "prevents completing another user's routine" do
      other_user = create(:user)
      other_routine = create(:workout_routine, user: other_user, is_completed: false)

      result = execute_graphql(
        query: mutation,
        variables: { routineId: other_routine.id.to_s },
        context: { current_user: user }
      )

      data = result["data"]["completeRoutine"]
      expect(data["errors"]).to include("Routine not found")
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = execute_graphql(
        query: mutation,
        variables: { routineId: routine.id.to_s },
        context: { current_user: nil }
      )

      expect(result["errors"]).to be_present
    end
  end
end
