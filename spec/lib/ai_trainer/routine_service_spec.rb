# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::RoutineService do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }

  describe '.generate' do
    context 'with valid WorkoutPrograms data' do
      it 'returns routine from WorkoutPrograms' do
        result = described_class.generate(user: user)
        expect(result[:routine_id]).to start_with('RT-')
        expect(result[:exercises]).to be_an(Array)
      end
    end

    context 'when generator returns error response' do
      before do
        # Simulate WorkoutPrograms returning nil (no program found)
        allow(AiTrainer::WorkoutPrograms).to receive(:get_workout).and_return(nil)
      end

      it 'returns nil when generator returns error' do
        result = described_class.generate(user: user)
        expect(result).to be_nil
      end
    end

    context 'with mocked generator' do
      let(:mock_routine) do
        {
          routine_id: 'RT-123',
          exercises: [
            { exercise_name: '벤치프레스', sets: 3, reps: 10 }
          ],
          notes: [ '오늘의 포인트' ]
        }
      end

      before do
        allow_any_instance_of(AiTrainer::RoutineGenerator).to receive(:generate).and_return(mock_routine)
      end

      it 'returns routine' do
        result = described_class.generate(user: user)
        expect(result[:routine_id]).to eq('RT-123')
      end

      it 'passes day_of_week to generator' do
        expect(AiTrainer::RoutineGenerator).to receive(:new)
          .with(user: user, day_of_week: 3)
          .and_call_original

        described_class.generate(user: user, day_of_week: 3)
      end

      context 'with condition' do
        let(:condition) { { sleep: 4, fatigue: 2 } }

        it 'applies condition to generator' do
          generator = instance_double(AiTrainer::RoutineGenerator)
          allow(AiTrainer::RoutineGenerator).to receive(:new).and_return(generator)
          allow(generator).to receive(:with_condition).and_return(generator)
          allow(generator).to receive(:generate).and_return(mock_routine)

          expect(generator).to receive(:with_condition).with(condition)
          described_class.generate(user: user, condition: condition)
        end
      end

      context 'with recent feedbacks' do
        let(:feedback1) do
          create(:workout_feedback, user: user, feedback_type: 'DIFFICULTY',
                                    feedback: '오늘 운동 좋았어요')
        end

        let(:feedbacks) { [ feedback1 ] }

        it 'applies feedbacks to generator' do
          generator = instance_double(AiTrainer::RoutineGenerator)
          allow(AiTrainer::RoutineGenerator).to receive(:new).and_return(generator)
          allow(generator).to receive(:with_feedbacks).and_return(generator)
          allow(generator).to receive(:generate).and_return(mock_routine)

          expect(generator).to receive(:with_feedbacks).with(feedbacks)
          described_class.generate(user: user, recent_feedbacks: feedbacks)
        end

        it 'adds feedback context to notes' do
          result = described_class.generate(user: user, recent_feedbacks: feedbacks)
          notes = result[:notes]
          expect(notes.last).to include('최근 피드백')
        end
      end
    end

    context 'when error occurs' do
      before do
        allow_any_instance_of(AiTrainer::RoutineGenerator).to receive(:generate)
          .and_raise(StandardError, 'Test error')
      end

      it 'returns nil' do
        result = described_class.generate(user: user)
        expect(result).to be_nil
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with(/RoutineService error/)
        described_class.generate(user: user)
      end
    end
  end

  describe '#format_feedback_context' do
    let(:service) { described_class.new(user: user) }

    it 'returns nil for empty feedbacks' do
      result = service.send(:format_feedback_context, [])
      expect(result).to be_nil
    end

    it 'formats feedback entries' do
      feedback = create(:workout_feedback, user: user, feedback_type: 'DIFFICULTY',
                                           feedback: '운동이 힘들었어요')
      result = service.send(:format_feedback_context, [ feedback ])
      expect(result).to include('최근 피드백')
      expect(result).to include('DIFFICULTY')
    end

    it 'truncates long feedback' do
      long_feedback = create(:workout_feedback, user: user, feedback_type: 'DIFFICULTY',
                                                feedback: 'a' * 100)
      result = service.send(:format_feedback_context, [ long_feedback ])
      expect(result.length).to be < 200
    end

    it 'limits to first 3 feedbacks' do
      feedbacks = 5.times.map do |i|
        create(:workout_feedback, user: user, feedback_type: 'DIFFICULTY',
                                  feedback: "피드백 #{i}")
      end
      result = service.send(:format_feedback_context, feedbacks)
      # Should only include first 3
      expect(result).to include('피드백 0')
      expect(result).to include('피드백 2')
      expect(result).not_to include('피드백 4')
    end
  end
end
