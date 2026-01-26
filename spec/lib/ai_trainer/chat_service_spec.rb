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
    let(:empty_context) { { used: false, prompt: "", sources: [] } }

    it 'includes user level' do
      prompt = service.send(:build_prompt, '운동 질문', empty_context)
      expect(prompt).to include('레벨: 3')
    end

    it 'includes user name' do
      prompt = service.send(:build_prompt, '운동 질문', empty_context)
      expect(prompt).to include('Test User')
    end

    it 'includes user message' do
      prompt = service.send(:build_prompt, '벤치프레스 자세가 궁금해요', empty_context)
      expect(prompt).to include('벤치프레스 자세가 궁금해요')
    end

    context 'without user profile' do
      let(:user_without_profile) { create(:user) }
      let(:service) { described_class.new(user: user_without_profile) }

      it 'defaults to level 1' do
        prompt = service.send(:build_prompt, '질문', empty_context)
        expect(prompt).to include('레벨: 1')
      end
    end

    context 'with RAG knowledge context' do
      let(:knowledge_context) do
        {
          used: true,
          prompt: "## 참고 지식\n벤치프레스는 가슴 운동의 핵심입니다.",
          sources: []
        }
      end

      it 'includes knowledge in prompt' do
        prompt = service.send(:build_prompt, '벤치프레스 자세가 궁금해요', knowledge_context)
        expect(prompt).to include('참고 지식')
        expect(prompt).to include('벤치프레스는 가슴 운동의 핵심')
      end
    end
  end

  describe '#extract_keywords' do
    it 'extracts meaningful words from message' do
      keywords = service.send(:extract_keywords, '마선호는 뭐라고 하나?')
      expect(keywords).to include('마선호는')
      expect(keywords).to include('마선호')
    end

    it 'removes Korean particles' do
      keywords = service.send(:extract_keywords, '벤치프레스를 어떻게 해야 하나요?')
      expect(keywords).to include('벤치프레스')
    end

    it 'filters out short words' do
      keywords = service.send(:extract_keywords, '나 운동 좀')
      expect(keywords).not_to include('나')
    end

    it 'handles punctuation' do
      keywords = service.send(:extract_keywords, '스쿼트 자세가 궁금해요!')
      expect(keywords).to include('스쿼트')
      expect(keywords).to include('자세가')
    end
  end

  describe '#search_with_keywords' do
    before do
      allow(RagSearchService).to receive(:search).and_return([])
    end

    it 'searches with extracted keywords' do
      service.send(:search_with_keywords, ['벤치프레스', '자세'])

      expect(RagSearchService).to have_received(:search).with('벤치프레스', limit: 2)
      expect(RagSearchService).to have_received(:search).with('자세', limit: 2)
    end

    it 'limits to first 5 keywords' do
      many_keywords = %w[a b c d e f g h]
      service.send(:search_with_keywords, many_keywords)

      expect(RagSearchService).to have_received(:search).exactly(5).times
    end

    it 'returns empty array for empty keywords' do
      result = service.send(:search_with_keywords, [])
      expect(result).to eq([])
    end

    it 'deduplicates results by id' do
      chunk1 = { id: 1, content: 'test1' }
      chunk2 = { id: 2, content: 'test2' }
      allow(RagSearchService).to receive(:search).and_return([chunk1, chunk2], [chunk1])

      result = service.send(:search_with_keywords, ['keyword1', 'keyword2'])
      expect(result.map { |r| r[:id] }).to eq([1, 2])
    end
  end

  describe '#retrieve_knowledge' do
    it 'returns knowledge context when chunks found' do
      chunks = [{ id: 1, content: 'test', source: { video_url: 'url' } }]
      allow(RagSearchService).to receive(:search).and_return(chunks)
      allow(RagSearchService).to receive(:build_context_prompt).and_return('context prompt')

      result = service.send(:retrieve_knowledge, '마선호 운동법')

      expect(result[:used]).to be true
      expect(result[:prompt]).to eq('context prompt')
    end

    it 'returns empty context when no chunks found' do
      allow(RagSearchService).to receive(:search).and_return([])

      result = service.send(:retrieve_knowledge, '없는 키워드')

      expect(result[:used]).to be false
      expect(result[:prompt]).to eq('')
    end

    it 'handles errors gracefully' do
      allow(RagSearchService).to receive(:search).and_raise(StandardError, 'DB error')

      result = service.send(:retrieve_knowledge, '테스트')

      expect(result[:used]).to be false
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
