# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RecordWorkout, type: :graphql do
  let(:user) { create(:user, :with_profile) }
  let(:routine) { create(:workout_routine, user: user) }

  let(:mutation) do
    <<~GRAPHQL
      mutation RecordWorkout($input: RecordWorkoutInput!) {
        recordWorkout(input: $input) {
          success
          workoutRecord {
            id
            date
            totalDuration
            completionStatus
          }
          error
        }
      }
    GRAPHQL
  end

  let(:workout_data) do
    {
      routineId: routine.id.to_s,
      date: Time.current.iso8601,
      exercises: [
        {
          exerciseName: "Bench Press",
          targetMuscle: "CHEST",
          plannedSets: 3,
          completedSets: [
            { setNumber: 1, reps: 10, weight: 60.0 },
            { setNumber: 2, reps: 8, weight: 65.0 },
            { setNumber: 3, reps: 6, weight: 70.0, rpe: 8 }
          ]
        }
      ],
      totalDuration: 3600,
      perceivedExertion: 7,
      completionStatus: "COMPLETED",
      caloriesBurned: 300,
      notes: "Great workout!"
    }
  end

  describe "when authenticated" do
    context "with valid input" do
      it "records the workout successfully" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: workout_data } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be true
        expect(data["workoutRecord"]).to be_present
        expect(data["workoutRecord"]["completionStatus"]).to eq("COMPLETED")
        expect(data["error"]).to be_nil
      end

      it "creates workout record in database" do
        expect {
          execute_graphql(
            query: mutation,
            variables: { input: { input: workout_data } },
            context: { current_user: user }
          )
        }.to change(WorkoutRecord, :count).by(1)
      end

      it "creates workout sets for exercises" do
        expect {
          execute_graphql(
            query: mutation,
            variables: { input: { input: workout_data } },
            context: { current_user: user }
          )
        }.to change(WorkoutSet, :count).by(3)
      end

      it "uses existing active session if present" do
        active_session = create(:workout_session, user: user, status: "active")

        result = RepstackBackendSchema.execute(
          mutation,
          variables: { input: { input: workout_data } },
          context: { current_user: user }
        )
        data = result["data"]["recordWorkout"]

        expect(data["success"]).to be true
        expect(WorkoutRecord.last.workout_session_id).to eq(active_session.id)
      end

      it "creates new session if no active session exists" do
        expect {
          execute_graphql(
            query: mutation,
            variables: { input: { input: workout_data } },
            context: { current_user: user }
          )
        }.to change(WorkoutSession, :count).by(1)
      end
    end

    context "with partial completion" do
      it "records partial workout" do
        partial_data = workout_data.merge(completionStatus: "PARTIAL")

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: partial_data } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be true
        expect(data["workoutRecord"]["completionStatus"]).to eq("PARTIAL")
      end
    end

    context "without exercises" do
      it "handles empty exercises array" do
        no_exercises_data = workout_data.merge(exercises: [])

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: no_exercises_data } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be true
      end
    end

    context "with invalid data" do
      it "returns error for invalid perceived exertion" do
        invalid_data = workout_data.merge(perceivedExertion: 15)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: invalid_data } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be false
        expect(data["error"]).to be_present
      end

      it "returns error for invalid duration" do
        invalid_data = workout_data.merge(totalDuration: -100)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: invalid_data } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be false
        expect(data["error"]).to be_present
      end
    end

    context "with optional fields" do
      it "works without calories burned" do
        data_without_calories = workout_data.except(:caloriesBurned)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: data_without_calories } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be true
      end

      it "works without notes" do
        data_without_notes = workout_data.except(:notes)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: data_without_notes } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be true
      end

      it "works without date (uses current time)" do
        data_without_date = workout_data.except(:date)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: data_without_date } },
          context: { current_user: user }
        )
        data = response["data"]["recordWorkout"]

        expect(data["success"]).to be true
        expect(data["workoutRecord"]["date"]).to be_present
      end
    end

    context "with set details" do
      it "records RPE for individual sets" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: workout_data } },
          context: { current_user: user }
        )

        expect(response["data"]["recordWorkout"]["success"]).to be true
        expect(WorkoutSet.last.rpe).to eq(8)
      end

      it "records set notes" do
        data_with_notes = workout_data.deep_dup
        data_with_notes[:exercises][0][:completedSets][0][:notes] = "Felt strong"

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: data_with_notes } },
          context: { current_user: user }
        )

        expect(response["data"]["recordWorkout"]["success"]).to be true
        expect(WorkoutSet.first.notes).to eq("Felt strong")
      end
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = RepstackBackendSchema.execute(
        mutation,
        variables: { input: { input: workout_data } },
        context: { current_user: nil }
      )

      data = result["data"]["recordWorkout"]
      expect(data["success"]).to be false
      expect(data["error"]).to be_present
    end
  end
end
