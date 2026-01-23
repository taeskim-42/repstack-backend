# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::FeedbackService do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user) }

  describe '.analyze_from_text' do
    context 'without API key (mock mode)' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      end

      it 'returns success' do
        result = described_class.analyze_from_text(user: user, text: '오늘 운동 좋았어요')
        expect(result[:success]).to be true
      end

      it 'returns message' do
        result = described_class.analyze_from_text(user: user, text: '오늘 운동 좋았어요')
        expect(result[:message]).to be_present
      end

      it 'returns insights' do
        result = described_class.analyze_from_text(user: user, text: '오늘 운동 좋았어요')
        expect(result[:insights]).to be_an(Array)
      end

      it 'returns adaptations' do
        result = described_class.analyze_from_text(user: user, text: '오늘 운동 좋았어요')
        expect(result[:adaptations]).to be_an(Array)
      end

      it 'returns recommendations' do
        result = described_class.analyze_from_text(user: user, text: '오늘 운동 좋았어요')
        expect(result[:next_workout_recommendations]).to be_an(Array)
      end
    end

    context 'with routine_id' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      end

      it 'accepts routine_id parameter' do
        result = described_class.analyze_from_text(user: user, text: '좋았어요', routine_id: 'test-123')
        expect(result[:success]).to be true
      end
    end

    context 'when error occurs' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.analyze_from_text(user: user, text: '테스트')
        expect(result[:success]).to be false
        expect(result[:error]).to include('피드백 분석 실패')
      end
    end
  end

  describe '#extract_json' do
    it 'extracts JSON from markdown code blocks' do
      text = "결과:\n```json\n{\"rating\": 4}\n```"
      result = service.send(:extract_json, text)
      expect(JSON.parse(result)['rating']).to eq(4)
    end

    it 'extracts JSON without markdown' do
      text = "분석 결과는 {\"rating\": 5} 입니다"
      result = service.send(:extract_json, text)
      expect(JSON.parse(result)['rating']).to eq(5)
    end

    it 'returns text if no JSON structure found' do
      text = "일반 텍스트"
      result = service.send(:extract_json, text)
      expect(result).to eq(text)
    end
  end

  describe '#save_feedback' do
    let(:data) do
      {
        'feedback_type' => 'DIFFICULTY', # Must be uppercase to match model validation
        'rating' => 4,
        'adaptations' => [ '다음에 무게 올리기' ]
      }
    end

    it 'creates feedback record with valid data' do
      expect do
        service.send(:save_feedback, data, '힘들었어요', nil)
      end.to change { user.workout_feedbacks.count }.by(1)
    end

    it 'sets correct values' do
      service.send(:save_feedback, data, '힘들었어요', nil)
      feedback = user.workout_feedbacks.last

      expect(feedback.feedback).to eq('힘들었어요')
      expect(feedback.feedback_type).to eq('DIFFICULTY')
      expect(feedback.rating).to eq(4)
      expect(feedback.would_recommend).to be true
    end

    it 'sets would_recommend to false for low rating' do
      data['rating'] = 2
      service.send(:save_feedback, data, '별로였어요', nil)
      feedback = user.workout_feedbacks.last

      expect(feedback.would_recommend).to be false
    end

    it 'handles routine_id' do
      service.send(:save_feedback, data, '좋았어요', 123)
      feedback = user.workout_feedbacks.last

      expect(feedback.routine_id).to eq(123)
    end

    it 'handles invalid feedback_type gracefully' do
      # lowercase 'general' is not in FEEDBACK_TYPES, so it will fail silently
      minimal_data = { 'feedback_type' => 'general', 'rating' => 3 }
      expect do
        service.send(:save_feedback, minimal_data, '테스트', nil)
      end.not_to change { user.workout_feedbacks.count }
    end
  end

  describe '#build_prompt' do
    it 'includes user text' do
      prompt = service.send(:build_prompt, '오늘 운동 힘들었어요')
      expect(prompt).to include('오늘 운동 힘들었어요')
    end

    it 'includes feedback types' do
      prompt = service.send(:build_prompt, '테스트')
      expect(prompt).to include('difficulty')
      expect(prompt).to include('pain')
      expect(prompt).to include('preference')
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

  describe '#mock_response' do
    it 'returns success' do
      result = service.send(:mock_response)
      expect(result[:success]).to be true
    end

    it 'returns message' do
      result = service.send(:mock_response)
      expect(result[:message]).to be_present
    end

    it 'returns empty arrays for recommendations' do
      result = service.send(:mock_response)
      expect(result[:next_workout_recommendations]).to eq([])
    end

    it 'returns insights and adaptations' do
      result = service.send(:mock_response)
      expect(result[:insights]).to be_an(Array)
      expect(result[:adaptations]).to be_an(Array)
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
          body: { content: [ { text: '{"rating": 4}' } ] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = service.send(:call_claude_api, 'test prompt')
      expect(result).to eq('{"rating": 4}')
    end

    it 'raises error on non-200 response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 500, body: 'Internal Server Error')

      expect { service.send(:call_claude_api, 'test prompt') }
        .to raise_error(RuntimeError, /Claude API returned 500/)
    end
  end

  describe '#parse_and_save_response' do
    let(:valid_response) do
      <<~JSON
        ```json
        {
          "feedback_type": "DIFFICULTY",
          "rating": 4,
          "insights": ["운동 강도가 적절했습니다"],
          "adaptations": ["다음에 무게 증가"],
          "next_workout_recommendations": ["스쿼트 무게 올리기"],
          "affected_exercises": ["스쿼트"],
          "affected_muscles": ["legs"],
          "message": "좋은 피드백 감사해요!"
        }
        ```
      JSON
    end

    it 'parses valid response' do
      result = service.send(:parse_and_save_response, valid_response, '좋았어요', nil)
      expect(result[:success]).to be true
      expect(result[:message]).to eq('좋은 피드백 감사해요!')
      expect(result[:insights]).to eq([ '운동 강도가 적절했습니다' ])
    end

    it 'saves feedback record' do
      expect { service.send(:parse_and_save_response, valid_response, '좋았어요', nil) }
        .to change { user.workout_feedbacks.count }.by(1)
    end

    it 'returns error on invalid JSON' do
      result = service.send(:parse_and_save_response, 'invalid json', '테스트', nil)
      expect(result[:success]).to be false
      expect(result[:error]).to include('파싱 실패')
    end

    it 'handles missing optional fields' do
      minimal_response = '{"feedback_type": "GENERAL", "rating": 3, "message": "OK"}'
      result = service.send(:parse_and_save_response, minimal_response, '테스트', nil)
      expect(result[:insights]).to eq([])
      expect(result[:adaptations]).to eq([])
      expect(result[:next_workout_recommendations]).to eq([])
      expect(result[:affected_exercises]).to eq([])
      expect(result[:affected_muscles]).to eq([])
    end
  end

  describe 'with API configured' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
    end

    it 'calls Claude API when configured' do
      mock_response = <<~JSON
        ```json
        {
          "feedback_type": "DIFFICULTY",
          "rating": 4,
          "insights": ["좋았어요"],
          "adaptations": ["무게 증가"],
          "next_workout_recommendations": [],
          "affected_exercises": [],
          "affected_muscles": [],
          "message": "감사합니다!"
        }
        ```
      JSON

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [ { text: mock_response } ] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = service.analyze_from_text('오늘 좋았어요')
      expect(result[:success]).to be true
      expect(result[:message]).to eq('감사합니다!')
    end
  end
end
