# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::ChatService do
  let(:user) { create(:user, name: 'Test User') }
  let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3) }
  let(:service) { described_class.new(user: user) }

  describe '.general_chat' do
    context 'without API key (mock mode)' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      end

      it 'returns success' do
        result = described_class.general_chat(user: user, message: '운동 질문')
        expect(result[:success]).to be true
      end

      it 'returns message' do
        result = described_class.general_chat(user: user, message: '운동 질문')
        expect(result[:message]).to be_present
      end
    end

    context 'when error occurs' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.general_chat(user: user, message: '테스트')
        expect(result[:success]).to be false
        expect(result[:message]).to include('죄송')
      end
    end
  end

  describe '#build_prompt' do
    it 'includes user level' do
      prompt = service.send(:build_prompt, '운동 질문')
      expect(prompt).to include('레벨: 3')
    end

    it 'includes user name' do
      prompt = service.send(:build_prompt, '운동 질문')
      expect(prompt).to include('Test User')
    end

    it 'includes user message' do
      prompt = service.send(:build_prompt, '벤치프레스 자세가 궁금해요')
      expect(prompt).to include('벤치프레스 자세가 궁금해요')
    end

    context 'without user profile' do
      let(:user_without_profile) { create(:user) }
      let(:service) { described_class.new(user: user_without_profile) }

      it 'defaults to level 1' do
        prompt = service.send(:build_prompt, '질문')
        expect(prompt).to include('레벨: 1')
      end
    end
  end

  describe 'with LlmGateway' do
    it 'uses LlmGateway for API calls' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: true,
        content: '운동 관련 조언입니다!',
        model: 'claude-3-5-haiku-20241022'
      })

      result = service.general_chat('운동 질문')
      expect(result[:success]).to be true
      expect(result[:message]).to eq('운동 관련 조언입니다!')

      expect(AiTrainer::LlmGateway).to have_received(:chat).with(
        hash_including(task: :general_chat)
      )
    end

    it 'returns error on LlmGateway failure' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: false,
        error: 'API error'
      })

      result = service.general_chat('운동 질문')
      expect(result[:success]).to be false
      expect(result[:message]).to include('죄송해요')
    end

    it 'handles exceptions gracefully' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')

      result = service.general_chat('운동 질문')
      expect(result[:success]).to be false
      expect(result[:message]).to include('죄송해요')
    end
  end
end
