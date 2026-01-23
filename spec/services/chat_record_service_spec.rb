# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatRecordService do
  let(:user) { create(:user) }

  describe '.record_exercise' do
    subject do
      described_class.record_exercise(
        user: user,
        exercise_name: exercise_name,
        weight: weight,
        reps: reps,
        sets: sets
      )
    end

    let(:exercise_name) { '벤치프레스' }
    let(:weight) { 60.0 }
    let(:reps) { 8 }
    let(:sets) { 1 }

    context 'with valid input' do
      it 'returns success' do
        expect(subject[:success]).to be true
      end

      it 'creates workout set' do
        expect { subject }.to change { WorkoutSet.count }.by(1)
      end

      it 'creates workout session' do
        expect { subject }.to change { user.workout_sessions.count }.by(1)
      end

      it 'records correct exercise name' do
        subject
        expect(WorkoutSet.last.exercise_name).to eq('벤치프레스')
      end

      it 'records correct weight' do
        subject
        expect(WorkoutSet.last.weight).to eq(60.0)
      end

      it 'records correct reps' do
        subject
        expect(WorkoutSet.last.reps).to eq(8)
      end

      it 'sets source as chat' do
        subject
        expect(WorkoutSet.last.source).to eq('chat')
      end
    end

    context 'with multiple sets' do
      let(:sets) { 4 }

      it 'creates multiple workout sets' do
        expect { subject }.to change { WorkoutSet.count }.by(4)
      end

      it 'assigns correct set numbers' do
        subject
        set_numbers = WorkoutSet.last(4).map(&:set_number)
        expect(set_numbers).to eq([ 1, 2, 3, 4 ])
      end
    end

    context 'with nil weight' do
      let(:weight) { nil }

      it 'records without weight' do
        expect(subject[:success]).to be true
        expect(WorkoutSet.last.weight).to be_nil
      end
    end

    context 'with existing active session' do
      let!(:active_session) do
        create(:workout_session, user: user, start_time: Time.current, end_time: nil)
      end

      it 'uses existing session' do
        expect { subject }.not_to change { user.workout_sessions.count }
      end

      it 'adds set to existing session' do
        subject
        expect(WorkoutSet.last.workout_session).to eq(active_session)
      end
    end

    context 'with existing today chat session' do
      let!(:chat_session) do
        create(:workout_session,
               user: user,
               start_time: Time.current,
               end_time: Time.current + 1.hour,
               source: 'chat')
      end

      it 'reuses today chat session' do
        expect { subject }.not_to change { user.workout_sessions.where(source: 'chat').count }
      end
    end

    context 'exercise name normalization' do
      context 'with abbreviation "벤치"' do
        let(:exercise_name) { '벤치' }

        it 'normalizes to 벤치프레스' do
          subject
          expect(WorkoutSet.last.exercise_name).to eq('벤치프레스')
        end
      end

      context 'with abbreviation "데드"' do
        let(:exercise_name) { '데드' }

        it 'normalizes to 데드리프트' do
          subject
          expect(WorkoutSet.last.exercise_name).to eq('데드리프트')
        end
      end

      context 'with full name' do
        let(:exercise_name) { '스쿼트' }

        it 'keeps full name' do
          subject
          expect(WorkoutSet.last.exercise_name).to eq('스쿼트')
        end
      end
    end

    context 'set numbering' do
      it 'increments set number for same exercise' do
        described_class.record_exercise(user: user, exercise_name: '벤치프레스', weight: 60, reps: 8)
        described_class.record_exercise(user: user, exercise_name: '벤치프레스', weight: 60, reps: 8)

        set_numbers = WorkoutSet.where(exercise_name: '벤치프레스').pluck(:set_number)
        expect(set_numbers).to eq([ 1, 2 ])
      end

      it 'resets set number for different exercise' do
        described_class.record_exercise(user: user, exercise_name: '벤치프레스', weight: 60, reps: 8)
        described_class.record_exercise(user: user, exercise_name: '스쿼트', weight: 80, reps: 10)

        bench_set = WorkoutSet.find_by(exercise_name: '벤치프레스')
        squat_set = WorkoutSet.find_by(exercise_name: '스쿼트')
        expect(bench_set.set_number).to eq(1)
        expect(squat_set.set_number).to eq(1)
      end
    end
  end
end
