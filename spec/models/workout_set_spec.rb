# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutSet, type: :model do
  let(:user) { create(:user) }
  let(:session) { create(:workout_session, user: user) }

  describe "associations" do
    it { is_expected.to belong_to(:workout_session) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:exercise_name) }

    it "validates weight_unit inclusion" do
      set = build(:workout_set, workout_session: session, weight_unit: "invalid")
      expect(set).not_to be_valid
    end

    it "requires either reps or duration" do
      set = build(:workout_set, workout_session: session, reps: nil, duration_seconds: nil)
      expect(set).not_to be_valid
      expect(set.errors[:base]).to include("Must have either reps or duration")
    end
  end

  describe "#volume" do
    it "calculates weight * reps" do
      set = build(:workout_set, workout_session: session, weight: 50, reps: 10)
      expect(set.volume).to eq(500)
    end

    it "returns 0 when weight or reps is missing" do
      set = build(:workout_set, workout_session: session, weight: nil, reps: 10)
      expect(set.volume).to eq(0)
    end
  end

  describe "#is_timed_exercise?" do
    it "returns true when duration is present" do
      set = build(:workout_set, workout_session: session, duration_seconds: 60, reps: nil)
      expect(set.is_timed_exercise?).to be true
    end

    it "returns false when duration is nil" do
      set = build(:workout_set, workout_session: session, duration_seconds: nil)
      expect(set.is_timed_exercise?).to be false
    end
  end

  describe "#is_weighted_exercise?" do
    it "returns true when weight and reps are present" do
      set = build(:workout_set, workout_session: session, weight: 50, reps: 10)
      expect(set.is_weighted_exercise?).to be true
    end

    it "returns false when weight is nil" do
      set = build(:workout_set, workout_session: session, weight: nil, reps: 10)
      expect(set.is_weighted_exercise?).to be false
    end
  end

  describe "#duration_formatted" do
    it "formats with minutes and seconds" do
      set = build(:workout_set, workout_session: session, duration_seconds: 90, reps: nil)
      expect(set.duration_formatted).to eq("1:30")
    end

    it "formats with only seconds" do
      set = build(:workout_set, workout_session: session, duration_seconds: 45, reps: nil)
      expect(set.duration_formatted).to eq("45s")
    end

    it "returns nil when duration is nil" do
      set = build(:workout_set, workout_session: session, duration_seconds: nil)
      expect(set.duration_formatted).to be_nil
    end
  end

  describe "#weight_in_kg" do
    it "returns weight as-is when unit is kg" do
      set = build(:workout_set, workout_session: session, weight: 50, weight_unit: "kg")
      expect(set.weight_in_kg).to eq(50)
    end

    it "converts from lbs to kg" do
      set = build(:workout_set, workout_session: session, weight: 100, weight_unit: "lbs")
      expect(set.weight_in_kg).to be_within(0.1).of(45.36)
    end
  end

  describe "#weight_in_lbs" do
    it "returns weight as-is when unit is lbs" do
      set = build(:workout_set, workout_session: session, weight: 100, weight_unit: "lbs")
      expect(set.weight_in_lbs).to eq(100)
    end

    it "converts from kg to lbs" do
      set = build(:workout_set, workout_session: session, weight: 50, weight_unit: "kg")
      expect(set.weight_in_lbs).to be_within(0.1).of(110.23)
    end
  end
end
