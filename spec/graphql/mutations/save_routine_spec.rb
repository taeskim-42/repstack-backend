# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SaveRoutine, type: :graphql do
  let(:user) { create(:user) }

  let(:mutation) do
    <<~GRAPHQL
      mutation SaveRoutine(
        $level: String!,
        $weekNumber: Int!,
        $dayNumber: Int!,
        $workoutType: String!,
        $dayOfWeek: String!,
        $estimatedDuration: Int!,
        $exercises: [ExerciseInput!]!
      ) {
        saveRoutine(input: {
          level: $level,
          weekNumber: $weekNumber,
          dayNumber: $dayNumber,
          workoutType: $workoutType,
          dayOfWeek: $dayOfWeek,
          estimatedDuration: $estimatedDuration,
          exercises: $exercises
        }) {
          workoutRoutine {
            id
            level
            weekNumber
            dayNumber
          }
          errors
        }
      }
    GRAPHQL
  end

  let(:exercises) do
    [
      {
        exerciseName: "푸시업",
        targetMuscle: "chest",
        orderIndex: 1,
        sets: 3,
        reps: 10,
        restDurationSeconds: 60,
        rangeOfMotion: "Full",
        howTo: "Keep your body straight",
        purpose: "Build chest strength"
      },
      {
        exerciseName: "스쿼트",
        targetMuscle: "legs",
        orderIndex: 2,
        sets: 3,
        reps: 10,
        restDurationSeconds: 90,
        rangeOfMotion: "Parallel",
        howTo: "Keep your back straight",
        purpose: "Build leg strength"
      }
    ]
  end

  let(:variables) do
    {
      level: "beginner",
      weekNumber: 1,
      dayNumber: 1,
      workoutType: "strength",
      dayOfWeek: "Monday",
      estimatedDuration: 45,
      exercises: exercises
    }
  end

  describe "when authenticated" do
    it "saves a new routine" do
      result = execute_graphql(
        query: mutation,
        variables: variables,
        context: { current_user: user }
      )

      data = result["data"]["saveRoutine"]
      expect(data["errors"]).to be_empty
      expect(data["workoutRoutine"]["level"]).to eq("beginner")
      expect(data["workoutRoutine"]["weekNumber"]).to eq(1)
      expect(data["workoutRoutine"]["dayNumber"]).to eq(1)
    end

    it "creates associated exercises" do
      result = execute_graphql(
        query: mutation,
        variables: variables,
        context: { current_user: user }
      )

      routine_id = result["data"]["saveRoutine"]["workoutRoutine"]["id"]
      routine = WorkoutRoutine.find(routine_id)
      expect(routine.routine_exercises.count).to eq(2)
    end

    it "validates level" do
      invalid_variables = variables.merge(level: "expert")
      result = execute_graphql(
        query: mutation,
        variables: invalid_variables,
        context: { current_user: user }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["message"]).to include("Invalid level")
    end

    it "validates day of week" do
      invalid_variables = variables.merge(dayOfWeek: "Someday")
      result = execute_graphql(
        query: mutation,
        variables: invalid_variables,
        context: { current_user: user }
      )

      expect(result["errors"]).to be_present
      expect(result["errors"].first["message"]).to include("Invalid day of week")
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = execute_graphql(
        query: mutation,
        variables: variables,
        context: { current_user: nil }
      )

      expect(result["errors"]).to be_present
    end
  end
end
