# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiTrainer::FitnessTestService do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, level_assessed_at: nil) }
  let(:service) { described_class.new(user: user) }

  describe "#evaluate" do
    context "with poor performance" do
      it "assigns level 1" do
        result = service.evaluate(pushup_count: 5, squat_count: 10, pullup_count: 1)

        expect(result[:success]).to be true
        expect(result[:assigned_level]).to eq(1)
        expect(result[:assigned_tier]).to eq("beginner")
        expect(result[:exercise_results][:pushup][:tier]).to eq(:poor)
      end
    end

    context "with fair performance" do
      it "assigns level 2-3" do
        result = service.evaluate(pushup_count: 15, squat_count: 20, pullup_count: 5)

        expect(result[:success]).to be true
        expect(result[:assigned_level]).to be_between(2, 3)
        expect(result[:exercise_results][:pushup][:tier]).to eq(:fair)
      end
    end

    context "with good performance" do
      it "assigns level 4-5" do
        result = service.evaluate(pushup_count: 30, squat_count: 40, pullup_count: 10)

        expect(result[:success]).to be true
        expect(result[:assigned_level]).to be_between(4, 5)
        expect(result[:assigned_tier]).to eq("intermediate")
        expect(result[:exercise_results][:pushup][:tier]).to eq(:good)
      end
    end

    context "with excellent performance" do
      it "assigns level 6" do
        # excellent tier = 4 points each, total 12 points = level 5-6
        result = service.evaluate(pushup_count: 45, squat_count: 65, pullup_count: 20)

        expect(result[:success]).to be true
        expect(result[:assigned_level]).to be_between(5, 6)
        expect(result[:assigned_tier]).to be_in(%w[intermediate advanced])
      end
    end

    context "with elite performance" do
      it "assigns level 7" do
        result = service.evaluate(pushup_count: 55, squat_count: 80, pullup_count: 30)

        expect(result[:success]).to be true
        expect(result[:assigned_level]).to eq(7)
        expect(result[:assigned_tier]).to eq("advanced")
      end
    end

    it "calculates fitness score between 20 and 100" do
      result = service.evaluate(pushup_count: 20, squat_count: 30, pullup_count: 8)

      expect(result[:fitness_score]).to be_between(20, 100)
    end

    it "provides recommendations for weak areas" do
      result = service.evaluate(pushup_count: 5, squat_count: 50, pullup_count: 1)

      expect(result[:recommendations]).to include(
        a_string_matching(/상체 밀기/)
      )
      expect(result[:recommendations]).to include(
        a_string_matching(/당기기/)
      )
    end
  end

  describe "#apply_to_profile" do
    it "updates user profile with test result" do
      result = service.evaluate(pushup_count: 25, squat_count: 35, pullup_count: 10)
      success = service.apply_to_profile(result)

      expect(success).to be true
      profile.reload
      expect(profile.numeric_level).to eq(result[:assigned_level])
      expect(profile.current_level).to eq(result[:assigned_tier])
      expect(profile.level_assessed_at).to be_present
      expect(profile.fitness_factors["fitness_test_result"]).to be_present
    end

    it "returns false when profile does not exist" do
      user_without_profile = create(:user)
      user_without_profile.user_profile&.destroy
      service_without_profile = described_class.new(user: user_without_profile.reload)

      result = service_without_profile.evaluate(pushup_count: 20, squat_count: 30, pullup_count: 8)
      success = service_without_profile.apply_to_profile(result)

      expect(success).to be false
    end
  end

  describe "scoring criteria" do
    it "scores pushups correctly" do
      # Poor: 0-9
      expect(service.evaluate(pushup_count: 9, squat_count: 0, pullup_count: 0)[:exercise_results][:pushup][:tier]).to eq(:poor)
      # Fair: 10-19
      expect(service.evaluate(pushup_count: 10, squat_count: 0, pullup_count: 0)[:exercise_results][:pushup][:tier]).to eq(:fair)
      # Good: 20-34
      expect(service.evaluate(pushup_count: 20, squat_count: 0, pullup_count: 0)[:exercise_results][:pushup][:tier]).to eq(:good)
      # Excellent: 35-49
      expect(service.evaluate(pushup_count: 35, squat_count: 0, pullup_count: 0)[:exercise_results][:pushup][:tier]).to eq(:excellent)
      # Elite: 50+
      expect(service.evaluate(pushup_count: 50, squat_count: 0, pullup_count: 0)[:exercise_results][:pushup][:tier]).to eq(:elite)
    end

    it "scores squats correctly" do
      # Poor: 0-14
      expect(service.evaluate(pushup_count: 0, squat_count: 14, pullup_count: 0)[:exercise_results][:squat][:tier]).to eq(:poor)
      # Fair: 15-29
      expect(service.evaluate(pushup_count: 0, squat_count: 15, pullup_count: 0)[:exercise_results][:squat][:tier]).to eq(:fair)
      # Good: 30-49
      expect(service.evaluate(pushup_count: 0, squat_count: 30, pullup_count: 0)[:exercise_results][:squat][:tier]).to eq(:good)
    end

    it "scores pullups correctly" do
      # Poor: 0-2
      expect(service.evaluate(pushup_count: 0, squat_count: 0, pullup_count: 2)[:exercise_results][:pullup][:tier]).to eq(:poor)
      # Fair: 3-7
      expect(service.evaluate(pushup_count: 0, squat_count: 0, pullup_count: 3)[:exercise_results][:pullup][:tier]).to eq(:fair)
      # Good: 8-14
      expect(service.evaluate(pushup_count: 0, squat_count: 0, pullup_count: 8)[:exercise_results][:pullup][:tier]).to eq(:good)
    end
  end
end
