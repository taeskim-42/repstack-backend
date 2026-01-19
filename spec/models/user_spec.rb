# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_presence_of(:name) }
    it { should have_secure_password }
  end

  describe "associations" do
    it { should have_one(:user_profile).dependent(:destroy) }
    it { should have_many(:workout_sessions).dependent(:destroy) }
    it { should have_many(:workout_routines).dependent(:destroy) }
  end

  describe "#has_active_workout?" do
    let(:user) { create(:user) }

    it "returns false when no sessions exist" do
      expect(user.has_active_workout?).to be false
    end

    it "returns false when all sessions are completed" do
      create(:workout_session, :completed, user: user)
      expect(user.has_active_workout?).to be false
    end

    it "returns true when an active session exists" do
      create(:workout_session, :active, user: user)
      expect(user.has_active_workout?).to be true
    end
  end

  describe "#current_workout_session" do
    let(:user) { create(:user) }

    it "returns nil when no active session" do
      expect(user.current_workout_session).to be_nil
    end

    it "returns the active session" do
      session = create(:workout_session, :active, user: user)
      expect(user.current_workout_session).to eq(session)
    end
  end

  describe "#total_workout_sessions" do
    let(:user) { create(:user) }

    it "returns 0 when no sessions" do
      expect(user.total_workout_sessions).to eq(0)
    end

    it "counts all sessions" do
      # total_workout_sessions only counts completed sessions (with end_time)
      create_list(:workout_session, 3, :completed, user: user)
      expect(user.total_workout_sessions).to eq(3)
    end
  end
end
