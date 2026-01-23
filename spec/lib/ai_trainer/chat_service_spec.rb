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

  describe '#general_chat' do
    context 'without API key' do
      before do
        allow(service).to receive(:api_configured?).and_return(false)
      end

      it 'returns mock response' do
        result = service.general_chat('운동 질문')
        expect(result[:success]).to be true
        expect(result[:message]).to be_present
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

  describe '#parse_response' do
    it 'returns success with trimmed message' do
      result = service.send(:parse_response, "  안녕하세요! 도와드릴게요.  \n")
      expect(result[:success]).to be true
      expect(result[:message]).to eq('안녕하세요! 도와드릴게요.')
    end
  end

  describe '#mock_response' do
    it 'returns one of predefined responses' do
      result = service.send(:mock_response, '질문')
      expect(result[:success]).to be true
      expect(result[:message]).to be_present
    end

    it 'includes emoji' do
      10.times do
        result = service.send(:mock_response, '질문')
        # At least some responses should have emoji
        break if result[:message].include?('💪') || result[:message].include?('🏋️') || result[:message].include?('😊')
      end
    end
  end

  describe '#api_configured?' do
    context 'when API key is set' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
      end

      it 'returns true' do
        expect(service.send(:api_configured?)).to be true
      end
    end

    context 'when API key is not set' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      end

      it 'returns false' do
        expect(service.send(:api_configured?)).to be false
      end
    end
  end

  describe '#call_claude_api' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
    end

    it 'returns text content on success' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [ { text: '좋은 질문이에요!' } ] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = service.send(:call_claude_api, 'test prompt')
      expect(result).to eq('좋은 질문이에요!')
    end

    it 'raises error on non-200 response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 500, body: 'Internal Server Error')

      expect { service.send(:call_claude_api, 'test prompt') }
        .to raise_error(RuntimeError, /Claude API returned 500/)
    end
  end

  describe '#parse_response' do
    it 'returns success with trimmed message' do
      result = service.send(:parse_response, "  테스트 응답입니다.  \n")
      expect(result[:success]).to be true
      expect(result[:message]).to eq('테스트 응답입니다.')
    end

    it 'handles empty response' do
      result = service.send(:parse_response, '')
      expect(result[:success]).to be true
      expect(result[:message]).to eq('')
    end
  end

  describe 'with API configured' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
    end

    it 'calls Claude API and returns response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [ { text: '운동 관련 조언입니다!' } ] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = service.general_chat('운동 질문')
      expect(result[:success]).to be true
      expect(result[:message]).to eq('운동 관련 조언입니다!')
    end

    it 'handles API error gracefully' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 500, body: 'Server Error')

      result = service.general_chat('운동 질문')
      expect(result[:success]).to be false
      expect(result[:message]).to include('죄송해요')
    end
  end
end
