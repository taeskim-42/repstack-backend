# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }

  describe '.generate_routine' do
    let(:mock_routine) do
      {
        routine_id: 'RT-123',
        exercises: [ { exercise_name: '벤치프레스', sets: 3, reps: 10 } ]
      }
    end

    before do
      allow_any_instance_of(AiTrainer::RoutineGenerator).to receive(:generate).and_return(mock_routine)
    end

    it 'returns routine from generator' do
      result = described_class.generate_routine(user: user)
      expect(result[:routine_id]).to eq('RT-123')
    end

    it 'passes day_of_week to generator' do
      expect(AiTrainer::RoutineGenerator).to receive(:new)
        .with(user: user, day_of_week: 3)
        .and_call_original

      described_class.generate_routine(user: user, day_of_week: 3)
    end

    it 'applies condition inputs when present' do
      generator = instance_double(AiTrainer::RoutineGenerator)
      allow(AiTrainer::RoutineGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:with_condition).and_return(generator)
      allow(generator).to receive(:generate).and_return(mock_routine)

      expect(generator).to receive(:with_condition).with({ energy: 3 })
      described_class.generate_routine(user: user, condition_inputs: { energy: 3 })
    end

    it 'does not apply condition inputs when empty' do
      generator = instance_double(AiTrainer::RoutineGenerator)
      allow(AiTrainer::RoutineGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:generate).and_return(mock_routine)

      expect(generator).not_to receive(:with_condition)
      described_class.generate_routine(user: user, condition_inputs: {})
    end

    it 'applies feedbacks when present' do
      feedbacks = [ double('feedback') ]
      generator = instance_double(AiTrainer::RoutineGenerator)
      allow(AiTrainer::RoutineGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:with_feedbacks).and_return(generator)
      allow(generator).to receive(:generate).and_return(mock_routine)

      expect(generator).to receive(:with_feedbacks).with(feedbacks)
      described_class.generate_routine(user: user, recent_feedbacks: feedbacks)
    end

    it 'does not apply feedbacks when nil' do
      generator = instance_double(AiTrainer::RoutineGenerator)
      allow(AiTrainer::RoutineGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:generate).and_return(mock_routine)

      expect(generator).not_to receive(:with_feedbacks)
      described_class.generate_routine(user: user, recent_feedbacks: nil)
    end
  end

  describe '.generate_level_test' do
    it 'returns test from LevelTestService' do
      service = instance_double(AiTrainer::LevelTestService)
      allow(AiTrainer::LevelTestService).to receive(:new).with(user: user).and_return(service)
      allow(service).to receive(:generate_test).and_return({ test_id: 'LT-123' })

      result = described_class.generate_level_test(user: user)
      expect(result[:test_id]).to eq('LT-123')
    end
  end

  describe '.evaluate_level_test' do
    let(:test_results) do
      {
        test_id: 'LT-123',
        exercises: [ { exercise_type: 'bench', weight_kg: 80, reps: 1 } ]
      }
    end

    it 'delegates to LevelTestService' do
      service = instance_double(AiTrainer::LevelTestService)
      allow(AiTrainer::LevelTestService).to receive(:new).with(user: user).and_return(service)
      allow(service).to receive(:evaluate_results).with(test_results).and_return({ passed: true })

      result = described_class.evaluate_level_test(user: user, test_results: test_results)
      expect(result[:passed]).to be true
    end
  end

  describe '.check_test_eligibility' do
    it 'delegates to LevelTestService' do
      service = instance_double(AiTrainer::LevelTestService)
      allow(AiTrainer::LevelTestService).to receive(:new).with(user: user).and_return(service)
      allow(service).to receive(:eligible_for_test?).and_return({ eligible: true })

      result = described_class.check_test_eligibility(user: user)
      expect(result[:eligible]).to be true
    end
  end

  describe '.constants' do
    it 'returns Constants module' do
      expect(described_class.constants).to eq(AiTrainer::Constants)
    end
  end
end
