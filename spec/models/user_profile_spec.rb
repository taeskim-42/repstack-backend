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
end
