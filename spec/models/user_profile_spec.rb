# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserProfile, type: :model do
  describe "validations" do
    it { should validate_inclusion_of(:current_level).in_array(%w[beginner intermediate advanced]) }
    # week_number and day_number have default values set via callback, so presence validation
    # is effectively always satisfied. We test numericality instead.
    it { should validate_numericality_of(:week_number).is_greater_than(0) }
    it { should validate_numericality_of(:day_number).is_in(1..7) }
    it { should validate_numericality_of(:height).is_greater_than(0).allow_nil }
    it { should validate_numericality_of(:weight).is_greater_than(0).allow_nil }
    it { should validate_numericality_of(:body_fat_percentage).is_in(0..100).allow_nil }
  end

  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "default values" do
    let(:user) { create(:user) }
    let(:profile) { create(:user_profile, user: user) }

    it "sets default current_level to beginner" do
      new_profile = user.build_user_profile
      new_profile.save!
      expect(new_profile.current_level).to eq("beginner")
    end

    it "sets default week_number to 1" do
      new_profile = user.build_user_profile
      new_profile.save!
      expect(new_profile.week_number).to eq(1)
    end

    it "sets default day_number to 1" do
      new_profile = user.build_user_profile
      new_profile.save!
      expect(new_profile.day_number).to eq(1)
    end
  end

  describe "#bmi" do
    let(:profile) { build(:user_profile, height: 175, weight: 70) }

    it "calculates BMI correctly" do
      # BMI = weight / (height_m^2) = 70 / (1.75^2) = 22.86
      expect(profile.bmi).to be_within(0.1).of(22.9)
    end

    it "returns nil when height is missing" do
      profile.height = nil
      expect(profile.bmi).to be_nil
    end

    it "returns nil when weight is missing" do
      profile.weight = nil
      expect(profile.bmi).to be_nil
    end
  end

  describe "#bmi_category" do
    let(:profile) { build(:user_profile, height: 175) }

    it "returns Underweight for BMI < 18.5" do
      profile.weight = 50 # BMI ≈ 16.3
      expect(profile.bmi_category).to eq("Underweight")
    end

    it "returns Normal for BMI 18.5-24.9" do
      profile.weight = 70 # BMI ≈ 22.9
      expect(profile.bmi_category).to eq("Normal")
    end

    it "returns Overweight for BMI 25-29.9" do
      profile.weight = 85 # BMI ≈ 27.8
      expect(profile.bmi_category).to eq("Overweight")
    end

    it "returns Obese for BMI >= 30" do
      profile.weight = 100 # BMI ≈ 32.7
      expect(profile.bmi_category).to eq("Obese")
    end
  end

  describe "#advance_day!" do
    let(:profile) { create(:user_profile, week_number: 1, day_number: 1) }

    it "increments day within week" do
      profile.advance_day!
      expect(profile.day_number).to eq(2)
      expect(profile.week_number).to eq(1)
    end

    it "advances to next week after day 7" do
      profile.update!(day_number: 7)
      profile.advance_day!
      expect(profile.day_number).to eq(1)
      expect(profile.week_number).to eq(2)
    end
  end

  describe "#advance_level!" do
    it "advances from beginner to intermediate" do
      profile = create(:user_profile, current_level: "beginner", week_number: 4, day_number: 5)
      profile.advance_level!

      expect(profile.current_level).to eq("intermediate")
      expect(profile.week_number).to eq(1)
      expect(profile.day_number).to eq(1)
    end

    it "advances from intermediate to advanced" do
      profile = create(:user_profile, current_level: "intermediate")
      profile.advance_level!

      expect(profile.current_level).to eq("advanced")
    end

    it "does nothing when already advanced" do
      profile = create(:user_profile, current_level: "advanced", week_number: 10)
      profile.advance_level!

      expect(profile.current_level).to eq("advanced")
      expect(profile.week_number).to eq(10)
    end
  end

  describe "#days_since_start" do
    let(:profile) { create(:user_profile, program_start_date: 10.days.ago) }

    it "calculates days since program start" do
      expect(profile.days_since_start).to eq(10)
    end

    it "returns 0 when no start date" do
      profile.update!(program_start_date: nil)
      expect(profile.days_since_start).to eq(0)
    end
  end

  describe "#level and #level=" do
    let(:profile) { create(:user_profile, numeric_level: 3) }

    it "returns numeric_level" do
      expect(profile.level).to eq(3)
    end

    it "returns 1 when numeric_level is nil" do
      profile.numeric_level = nil
      expect(profile.level).to eq(1)
    end

    it "sets numeric_level" do
      profile.level = 5
      expect(profile.numeric_level).to eq(5)
    end
  end

  describe "#tier" do
    it "returns beginner for levels 1-2" do
      profile = build(:user_profile, numeric_level: 1)
      expect(profile.tier).to eq("beginner")

      profile.numeric_level = 2
      expect(profile.tier).to eq("beginner")
    end

    it "returns intermediate for levels 3-5" do
      profile = build(:user_profile, numeric_level: 3)
      expect(profile.tier).to eq("intermediate")

      profile.numeric_level = 5
      expect(profile.tier).to eq("intermediate")
    end

    it "returns advanced for levels 6-8" do
      profile = build(:user_profile, numeric_level: 6)
      expect(profile.tier).to eq("advanced")

      profile.numeric_level = 8
      expect(profile.tier).to eq("advanced")
    end

    it "returns beginner for unknown level" do
      profile = build(:user_profile)
      profile.numeric_level = 99
      expect(profile.tier).to eq("beginner")
    end
  end

  describe "#tier_korean" do
    let(:profile) { build(:user_profile) }

    it "returns 초급 for beginner" do
      profile.numeric_level = 1
      expect(profile.tier_korean).to eq("초급")
    end

    it "returns 중급 for intermediate" do
      profile.numeric_level = 4
      expect(profile.tier_korean).to eq("중급")
    end

    it "returns 고급 for advanced" do
      profile.numeric_level = 7
      expect(profile.tier_korean).to eq("고급")
    end
  end

  describe "#grade" do
    let(:profile) { build(:user_profile) }

    it "returns 정상인 for levels 1-3" do
      profile.numeric_level = 2
      expect(profile.grade).to eq("정상인")
    end

    it "returns 건강인 for levels 4-5" do
      profile.numeric_level = 4
      expect(profile.grade).to eq("건강인")
    end

    it "returns 운동인 for levels 6-8" do
      profile.numeric_level = 7
      expect(profile.grade).to eq("운동인")
    end

    it "returns 정상인 for unknown level" do
      profile.numeric_level = 99
      expect(profile.grade).to eq("정상인")
    end
  end

  describe "#can_take_level_test?" do
    let(:profile) { create(:user_profile, numeric_level: 3) }

    it "returns false if level is max (8)" do
      profile.numeric_level = 8
      expect(profile.can_take_level_test?).to be false
    end

    it "returns true if never tested" do
      profile.last_level_test_at = nil
      expect(profile.can_take_level_test?).to be true
    end

    it "returns true if last test was over 7 days ago" do
      profile.last_level_test_at = 8.days.ago
      expect(profile.can_take_level_test?).to be true
    end

    it "returns false if last test was within 7 days" do
      profile.last_level_test_at = 3.days.ago
      expect(profile.can_take_level_test?).to be false
    end
  end

  describe "#days_until_next_test" do
    let(:profile) { create(:user_profile, numeric_level: 3) }

    it "returns 0 if can take test" do
      profile.last_level_test_at = nil
      expect(profile.days_until_next_test).to eq(0)
    end

    it "returns remaining days until test available" do
      profile.last_level_test_at = 3.days.ago
      expect(profile.days_until_next_test).to eq(4)
    end
  end

  describe "#increment_workout_count!" do
    let(:profile) { create(:user_profile, total_workouts_completed: 5) }

    it "increments total_workouts_completed" do
      profile.increment_workout_count!
      expect(profile.reload.total_workouts_completed).to eq(6)
    end
  end

  describe "#bmi_category with nil" do
    let(:profile) { build(:user_profile, height: nil, weight: nil) }

    it "returns Unknown when BMI cannot be calculated" do
      expect(profile.bmi_category).to eq("Unknown")
    end
  end

  describe "sync_level_tier callback" do
    let(:profile) { create(:user_profile, numeric_level: 2) }

    it "syncs current_level when numeric_level changes" do
      profile.numeric_level = 6
      profile.save!
      expect(profile.current_level).to eq("advanced")
    end
  end
end
