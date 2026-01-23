# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoutineExercise, type: :model do
  let(:workout_routine) { create(:workout_routine) }
  let(:routine_exercise) do
    create(:routine_exercise,
           workout_routine: workout_routine,
           exercise_name: "푸시업",
           target_muscle: "chest",
           order_index: 1,
           sets: 3,
           reps: 10,
           weight: 20,
           rest_duration_seconds: 90)
  end

  describe "associations" do
    it { is_expected.to belong_to(:workout_routine) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:exercise_name) }
    it { is_expected.to validate_presence_of(:order_index) }

    it "validates exercise_name length" do
      expect(build(:routine_exercise, exercise_name: "a")).not_to be_valid
      expect(build(:routine_exercise, exercise_name: "ab")).to be_valid
    end

    it "validates sets is greater than 0" do
      expect(build(:routine_exercise, sets: 0)).not_to be_valid
      expect(build(:routine_exercise, sets: 1)).to be_valid
    end

    it "validates reps is greater than 0" do
      expect(build(:routine_exercise, reps: 0)).not_to be_valid
      expect(build(:routine_exercise, reps: 1)).to be_valid
    end

    it "validates bpm is in range 60-200" do
      expect(build(:routine_exercise, bpm: 59)).not_to be_valid
      expect(build(:routine_exercise, bpm: 60)).to be_valid
      expect(build(:routine_exercise, bpm: 200)).to be_valid
      expect(build(:routine_exercise, bpm: 201)).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:exercise1) { create(:routine_exercise, workout_routine: workout_routine, order_index: 2, target_muscle: "chest", bpm: nil) }
    let!(:exercise2) { create(:routine_exercise, workout_routine: workout_routine, order_index: 1, target_muscle: "legs", weight: 50, bpm: nil) }
    let!(:cardio_exercise) { create(:routine_exercise, workout_routine: workout_routine, order_index: 3, bpm: 120, target_muscle: "cardio") }

    describe ".ordered" do
      it "orders by order_index" do
        expect(workout_routine.routine_exercises.ordered.map(&:order_index)).to eq([ 1, 2, 3 ])
      end
    end

    describe ".by_muscle" do
      it "filters by muscle group" do
        expect(workout_routine.routine_exercises.by_muscle("chest")).to include(exercise1)
        expect(workout_routine.routine_exercises.by_muscle("chest")).not_to include(exercise2)
      end
    end

    describe ".with_weight" do
      it "returns exercises with weight" do
        expect(workout_routine.routine_exercises.with_weight).to include(exercise2)
      end
    end

    describe ".cardio" do
      it "returns exercises with bpm" do
        expect(workout_routine.routine_exercises.cardio).to include(cardio_exercise)
        expect(workout_routine.routine_exercises.cardio).not_to include(exercise1)
      end
    end

    describe ".strength" do
      it "returns exercises without bpm" do
        expect(workout_routine.routine_exercises.strength).to include(exercise1, exercise2)
        expect(workout_routine.routine_exercises.strength).not_to include(cardio_exercise)
      end
    end
  end

  describe "#estimated_exercise_duration" do
    it "calculates duration based on sets and rest time" do
      exercise = build(:routine_exercise, sets: 3, rest_duration_seconds: 60)
      duration = exercise.estimated_exercise_duration
      expect(duration).to be > 0
    end

    it "returns 0 when sets is nil" do
      exercise = build(:routine_exercise, sets: nil)
      expect(exercise.estimated_exercise_duration).to eq(0)
    end
  end

  describe "#rest_duration_formatted" do
    it "formats duration with minutes and seconds" do
      exercise = build(:routine_exercise, rest_duration_seconds: 90)
      expect(exercise.rest_duration_formatted).to eq("1:30")
    end

    it "formats duration with only seconds" do
      exercise = build(:routine_exercise, rest_duration_seconds: 45)
      expect(exercise.rest_duration_formatted).to eq("45s")
    end

    it "returns nil when rest_duration_seconds is nil" do
      exercise = build(:routine_exercise, rest_duration_seconds: nil)
      expect(exercise.rest_duration_formatted).to be_nil
    end
  end

  describe "#is_cardio?" do
    it "returns true when bpm is present" do
      exercise = build(:routine_exercise, bpm: 120)
      expect(exercise.is_cardio?).to be true
    end

    it "returns false when bpm is nil" do
      exercise = build(:routine_exercise, bpm: nil)
      expect(exercise.is_cardio?).to be false
    end
  end

  describe "#is_strength?" do
    it "returns true when weight is present and bpm is nil" do
      exercise = build(:routine_exercise, bpm: nil, weight: 50)
      expect(exercise.is_strength?).to be true
    end

    it "returns true when reps is present and bpm is nil" do
      exercise = build(:routine_exercise, bpm: nil, reps: 10, weight: nil)
      expect(exercise.is_strength?).to be true
    end

    it "returns false when bpm is present" do
      exercise = build(:routine_exercise, bpm: 120, weight: 50)
      expect(exercise.is_strength?).to be false
    end
  end

  describe "#exercise_summary" do
    it "includes sets and reps" do
      exercise = build(:routine_exercise, sets: 3, reps: 10, weight: nil, bpm: nil, rest_duration_seconds: nil)
      expect(exercise.exercise_summary).to include("3x10")
    end

    it "includes weight when present" do
      exercise = build(:routine_exercise, sets: 3, reps: 10, weight: 50, bpm: nil)
      expect(exercise.exercise_summary).to include("50")
      expect(exercise.exercise_summary).to include("kg")
    end

    it "includes bpm when present" do
      exercise = build(:routine_exercise, sets: 3, reps: 10, bpm: 120)
      expect(exercise.exercise_summary).to include("120 BPM")
    end

    it "includes rest duration" do
      exercise = build(:routine_exercise, sets: 3, reps: 10, rest_duration_seconds: 60)
      expect(exercise.exercise_summary).to include("Rest:")
    end
  end

  describe "#target_muscle_group" do
    it "maps chest to Chest" do
      expect(build(:routine_exercise, target_muscle: "chest").target_muscle_group).to eq("Chest")
    end

    it "maps back to Back" do
      expect(build(:routine_exercise, target_muscle: "back").target_muscle_group).to eq("Back")
    end

    it "maps legs to Legs" do
      expect(build(:routine_exercise, target_muscle: "legs").target_muscle_group).to eq("Legs")
    end

    it "maps arms to Arms" do
      expect(build(:routine_exercise, target_muscle: "arms").target_muscle_group).to eq("Arms")
    end

    it "maps core to Core" do
      expect(build(:routine_exercise, target_muscle: "core").target_muscle_group).to eq("Core")
    end

    it "maps cardio to Cardio" do
      expect(build(:routine_exercise, target_muscle: "cardio").target_muscle_group).to eq("Cardio")
    end

    it "maps shoulders to Shoulders" do
      expect(build(:routine_exercise, target_muscle: "shoulders").target_muscle_group).to eq("Shoulders")
    end

    it "returns titleized name for unknown muscle" do
      expect(build(:routine_exercise, target_muscle: "unknown_muscle").target_muscle_group).to eq("Unknown Muscle")
    end

    it "returns Other for nil" do
      expect(build(:routine_exercise, target_muscle: nil).target_muscle_group).to eq("Other")
    end
  end

  describe ".muscle_group_distribution" do
    before do
      create(:routine_exercise, workout_routine: workout_routine, target_muscle: "chest")
      create(:routine_exercise, workout_routine: workout_routine, target_muscle: "chest")
      create(:routine_exercise, workout_routine: workout_routine, target_muscle: "legs")
    end

    it "returns count by muscle group" do
      distribution = RoutineExercise.muscle_group_distribution
      expect(distribution["chest"]).to eq(2)
      expect(distribution["legs"]).to eq(1)
    end
  end

  describe ".average_sets_per_exercise" do
    before do
      create(:routine_exercise, workout_routine: workout_routine, sets: 3)
      create(:routine_exercise, workout_routine: workout_routine, sets: 4)
      create(:routine_exercise, workout_routine: workout_routine, sets: 5)
    end

    it "returns average sets" do
      expect(RoutineExercise.average_sets_per_exercise).to eq(4.0)
    end
  end
end
