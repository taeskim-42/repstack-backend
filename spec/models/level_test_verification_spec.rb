# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LevelTestVerification, type: :model do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, numeric_level: 3, height: 175) }

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:level_test_verification, user: user) }

    it { should validate_presence_of(:test_id) }
    it { should validate_uniqueness_of(:test_id) }
    it { should validate_presence_of(:current_level) }
    it { should validate_presence_of(:target_level) }

    # Note: status has a default value set in callback, so presence validation is implicit
    it 'validates status inclusion' do
      verification = build(:level_test_verification, status: 'invalid')
      expect(verification).not_to be_valid
    end

    it 'validates current_level range' do
      verification = build(:level_test_verification, current_level: 10)
      expect(verification).not_to be_valid
    end

    it 'validates target_level range' do
      verification = build(:level_test_verification, target_level: 1)
      expect(verification).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:pending_verification) { create(:level_test_verification, user: user, status: 'pending') }
    let!(:passed_verification) { create(:level_test_verification, :passed, user: user) }
    let!(:failed_verification) { create(:level_test_verification, :failed, user: user) }

    it 'filters by pending status' do
      expect(described_class.pending).to include(pending_verification)
      expect(described_class.pending).not_to include(passed_verification)
    end

    it 'filters by passed status' do
      expect(described_class.passed).to include(passed_verification)
      expect(described_class.passed).not_to include(pending_verification)
    end

    it 'filters by failed status' do
      expect(described_class.failed).to include(failed_verification)
      expect(described_class.failed).not_to include(passed_verification)
    end

    it 'orders by recent' do
      expect(described_class.recent.first).to eq(failed_verification)
    end
  end

  describe '#all_exercises_passed?' do
    it 'returns true when all exercises pass' do
      verification = create(:level_test_verification, :with_exercises, user: user)
      expect(verification.all_exercises_passed?).to be true
    end

    it 'returns false when any exercise fails' do
      verification = create(:level_test_verification, :failed, user: user)
      expect(verification.all_exercises_passed?).to be false
    end

    it 'returns false when exercises is empty' do
      verification = create(:level_test_verification, user: user, exercises: [])
      expect(verification.all_exercises_passed?).to be false
    end
  end

  describe '#exercise_result' do
    let(:verification) { create(:level_test_verification, :with_exercises, user: user) }

    it 'returns exercise by type' do
      result = verification.exercise_result(:bench)
      expect(result['exercise_type']).to eq('bench')
      expect(result['weight_kg']).to eq(70.0)
    end

    it 'returns nil for non-existent exercise' do
      result = verification.exercise_result(:unknown)
      expect(result).to be_nil
    end
  end

  describe '#complete_as_passed!' do
    let(:verification) { create(:level_test_verification, :with_exercises, user: user) }

    it 'updates verification status to passed' do
      verification.complete_as_passed!

      expect(verification.status).to eq('passed')
      expect(verification.passed).to be true
      expect(verification.new_level).to eq(4)
      expect(verification.completed_at).to be_present
    end

    it 'updates user profile level' do
      verification.complete_as_passed!

      profile.reload
      expect(profile.numeric_level).to eq(4)
      expect(profile.last_level_test_at).to be_present
    end
  end

  describe '#complete_as_failed!' do
    let(:verification) { create(:level_test_verification, user: user) }

    it 'updates verification status to failed' do
      verification.complete_as_failed!(feedback: 'Keep trying!')

      expect(verification.status).to eq('failed')
      expect(verification.passed).to be false
      expect(verification.new_level).to eq(3)
      expect(verification.ai_feedback).to eq('Keep trying!')
      expect(verification.completed_at).to be_present
    end
  end

  describe '#add_exercise_result' do
    let(:verification) { create(:level_test_verification, user: user) }

    it 'adds exercise result' do
      verification.add_exercise_result(
        exercise_type: :bench,
        weight_kg: 70.0,
        passed: true,
        pose_score: 85.0,
        form_issues: []
      )

      expect(verification.exercises.length).to eq(1)
      expect(verification.exercises.first['exercise_type']).to eq('bench')
      expect(verification.exercises.first['passed']).to be true
    end

    it 'replaces existing exercise of same type' do
      verification.add_exercise_result(
        exercise_type: :bench,
        weight_kg: 60.0,
        passed: false
      )

      verification.add_exercise_result(
        exercise_type: :bench,
        weight_kg: 70.0,
        passed: true
      )

      bench_results = verification.exercises.select { |e| e['exercise_type'] == 'bench' }
      expect(bench_results.length).to eq(1)
      expect(bench_results.first['weight_kg']).to eq(70.0)
    end

    it 'includes verified_at timestamp' do
      verification.add_exercise_result(
        exercise_type: :squat,
        weight_kg: 90.0,
        passed: true
      )

      expect(verification.exercises.first['verified_at']).to be_present
    end
  end

  describe 'callbacks' do
    it 'sets default status on create' do
      verification = LevelTestVerification.create!(
        user: user,
        test_id: "LTV-test-#{SecureRandom.hex(4)}",
        current_level: 3,
        target_level: 4
      )

      expect(verification.status).to eq('pending')
      expect(verification.exercises).to eq([])
      expect(verification.started_at).to be_present
    end
  end
end
