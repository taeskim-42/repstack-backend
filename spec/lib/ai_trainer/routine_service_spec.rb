# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::RoutineService do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }

  describe '#merge_feedback_preferences (D12)' do
    let(:service) { described_class.new(user: user) }

    let(:hard_feedback) do
      double('feedback', feedback_type: 'too_hard', exercise_name: '벤치프레스')
    end

    let(:easy_feedback) do
      double('feedback', feedback_type: 'too_easy', exercise_name: nil)
    end

    let(:enjoyed_feedback) do
      double('feedback', feedback_type: 'enjoyed', exercise_name: '데드리프트')
    end

    context 'with no feedbacks' do
      it 'returns the original condition unchanged' do
        expect(service.send(:merge_feedback_preferences, 'cond', nil)).to eq('cond')
        expect(service.send(:merge_feedback_preferences, { notes: 'x' }, [])).to eq(notes: 'x')
      end
    end

    context 'with nil condition' do
      it 'wraps preferences in a notes hash' do
        result = service.send(:merge_feedback_preferences, nil, [ hard_feedback ])
        expect(result[:notes]).to include('회피 운동: 벤치프레스')
        expect(result[:notes]).to include('강도 조정: lower')
      end
    end

    context 'with string condition' do
      it 'appends preferences to the condition text' do
        result = service.send(:merge_feedback_preferences, '에너지 낮음', [ enjoyed_feedback ])
        expect(result).to start_with('에너지 낮음')
        expect(result).to include('선호 운동: 데드리프트')
      end
    end

    context 'with hash condition having existing notes' do
      it 'concatenates preferences into notes' do
        cond = { energy_level: 2, notes: 'existing' }
        result = service.send(:merge_feedback_preferences, cond, [ easy_feedback ])
        expect(result[:energy_level]).to eq(2)
        expect(result[:notes]).to include('existing')
        expect(result[:notes]).to include('강도 조정: higher')
      end
    end

    context 'with feedbacks that produce no preferences' do
      let(:noisy_feedback) do
        double('feedback', feedback_type: 'unknown_type', exercise_name: nil)
      end

      it 'returns the original condition unchanged' do
        expect(service.send(:merge_feedback_preferences, 'x', [ noisy_feedback ])).to eq('x')
      end
    end
  end

  describe '.generate dispatch (D12)' do
    it 'routes through ToolBasedRoutineGenerator (single path)' do
      generator = instance_double(AiTrainer::ToolBasedRoutineGenerator)
      allow(AiTrainer::ToolBasedRoutineGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:with_goal).and_return(generator)
      allow(generator).to receive(:with_condition).and_return(generator)
      allow(generator).to receive(:generate).and_return(nil)

      described_class.generate(user: user, goal: 'hypertrophy')

      expect(AiTrainer::ToolBasedRoutineGenerator).to have_received(:new).with(hash_including(user: user))
      expect(generator).to have_received(:with_goal).with('hypertrophy')
    end

    it 'merges feedback preferences into condition before calling generator' do
      hard_feedback = double('feedback', feedback_type: 'too_hard', exercise_name: '벤치프레스')
      generator = instance_double(AiTrainer::ToolBasedRoutineGenerator)
      allow(AiTrainer::ToolBasedRoutineGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:with_goal).and_return(generator)
      allow(generator).to receive(:with_condition).and_return(generator)
      allow(generator).to receive(:generate).and_return(nil)

      described_class.generate(user: user, recent_feedbacks: [ hard_feedback ])

      expect(generator).to have_received(:with_condition) do |arg|
        expect(arg[:notes]).to include('벤치프레스')
      end
    end
  end
end
