# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkoutRoutine, type: :model do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, current_level: 'beginner', week_number: 1, day_number: 1) }
  let(:routine) { create(:workout_routine, user: user) }

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:routine_exercises).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_inclusion_of(:level).in_array(%w[beginner intermediate advanced]) }
    it { is_expected.to validate_presence_of(:week_number) }
    it { is_expected.to validate_presence_of(:day_number) }
    # generated_at is set by callback, so we test differently
    it 'requires generated_at after callback' do
      routine = build(:workout_routine)
      routine.valid?
      expect(routine.generated_at).to be_present
    end
  end

  describe 'scopes' do
    let!(:beginner_routine) { create(:workout_routine, user: user, level: 'beginner') }
    let!(:intermediate_routine) { create(:workout_routine, user: user, level: 'intermediate') }
    let!(:completed_routine) { create(:workout_routine, user: user, is_completed: true) }

    describe '.by_level' do
      it 'returns routines for the specified level' do
        expect(described_class.by_level('beginner')).to include(beginner_routine)
        expect(described_class.by_level('beginner')).not_to include(intermediate_routine)
      end
    end

    describe '.by_week' do
      it 'returns routines for the specified week' do
        expect(described_class.by_week(1)).to include(beginner_routine)
      end
    end

    describe '.by_day' do
      it 'returns routines for the specified day' do
        expect(described_class.by_day(1)).to include(beginner_routine)
      end
    end

    describe '.completed' do
      it 'returns only completed routines' do
        expect(described_class.completed).to include(completed_routine)
        expect(described_class.completed).not_to include(beginner_routine)
      end
    end

    describe '.pending' do
      it 'returns only pending routines' do
        expect(described_class.pending).to include(beginner_routine)
        expect(described_class.pending).not_to include(completed_routine)
      end
    end

    describe '.recent' do
      it 'returns routines ordered by generated_at desc' do
        routines = described_class.recent
        expect(routines.first.generated_at).to be >= routines.last.generated_at
      end
    end
  end

  describe '#complete!' do
    it 'marks the routine as completed' do
      routine.complete!
      expect(routine.reload.is_completed).to be true
      expect(routine.completed_at).to be_present
    end

    it 'advances user to next day' do
      expect(profile.day_number).to eq(1)
      routine.complete!
      expect(profile.reload.day_number).to eq(2)
    end
  end

  describe '#total_exercises' do
    it 'returns the count of routine exercises' do
      create_list(:routine_exercise, 3, workout_routine: routine)
      expect(routine.total_exercises).to eq(3)
    end
  end

  describe '#total_sets' do
    it 'returns the sum of sets from all exercises' do
      create(:routine_exercise, workout_routine: routine, sets: 3)
      create(:routine_exercise, workout_routine: routine, sets: 4)
      expect(routine.total_sets).to eq(7)
    end
  end

  describe '#estimated_duration_formatted' do
    context 'when estimated_duration is nil' do
      it 'returns nil' do
        routine.estimated_duration = nil
        expect(routine.estimated_duration_formatted).to be_nil
      end
    end

    context 'when estimated_duration is less than 60 minutes' do
      it 'returns minutes only' do
        routine.estimated_duration = 45
        expect(routine.estimated_duration_formatted).to eq('45m')
      end
    end

    context 'when estimated_duration is 60 minutes or more' do
      it 'returns hours and minutes' do
        routine.estimated_duration = 90
        expect(routine.estimated_duration_formatted).to eq('1h 30m')
      end
    end
  end

  describe '#workout_summary' do
    before do
      create(:routine_exercise, workout_routine: routine, target_muscle: 'chest')
      create(:routine_exercise, workout_routine: routine, target_muscle: 'back')
    end

    it 'returns a summary hash' do
      summary = routine.workout_summary
      expect(summary[:level]).to eq(routine.level)
      expect(summary[:week]).to eq(routine.week_number)
      expect(summary[:day]).to eq(routine.day_number)
      expect(summary[:exercises]).to eq(2)
      expect(summary[:muscle_groups]).to include('chest', 'back')
    end
  end

  describe '#day_name' do
    it 'returns the correct day name' do
      routine.day_number = 1
      expect(routine.day_name).to eq('Monday')

      routine.day_number = 5
      expect(routine.day_name).to eq('Friday')

      routine.day_number = 7
      expect(routine.day_name).to eq('Sunday')
    end
  end

  describe '.for_user_current_program' do
    context 'when user has a profile' do
      let!(:matching_routine) do
        create(:workout_routine, user: user, level: 'beginner', week_number: 1, day_number: 1, is_completed: false)
      end

      let!(:non_matching_routine) do
        create(:workout_routine, user: user, level: 'intermediate', week_number: 1, day_number: 1)
      end

      it 'returns routines matching current program' do
        result = described_class.for_user_current_program(user)
        expect(result).to include(matching_routine)
        expect(result).not_to include(non_matching_routine)
      end
    end

    context 'when user has no profile' do
      let(:user_without_profile) { create(:user) }

      it 'returns empty relation' do
        result = described_class.for_user_current_program(user_without_profile)
        expect(result).to be_empty
      end
    end
  end

  describe 'callbacks' do
    describe '#set_generated_at' do
      it 'sets generated_at on create if not provided' do
        new_routine = described_class.new(user: user, level: 'beginner', week_number: 1, day_number: 1)
        new_routine.valid?
        expect(new_routine.generated_at).to be_present
      end

      it 'does not override existing generated_at' do
        specific_time = 1.day.ago
        new_routine = described_class.new(user: user, level: 'beginner', week_number: 1, day_number: 1, generated_at: specific_time)
        new_routine.valid?
        expect(new_routine.generated_at).to be_within(1.second).of(specific_time)
      end
    end
  end
end
