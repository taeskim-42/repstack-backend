# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::FeedbackService do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user) }

  describe '.analyze_from_text' do
    context 'without API key (mock mode via LlmGateway)' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API not configured'
        })
      end

      it 'returns success (falls back to mock)' do
        result = described_class.analyze_from_text(user: user, text: '오늘 운동 좋았어요')
        expect(result[:success]).to be true
      end

      it 'returns message from mock' do
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
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API not configured'
        })
      end

      it 'accepts routine_id parameter' do
        result = described_class.analyze_from_text(user: user, text: '좋았어요', routine_id: 'test-123')
        expect(result[:success]).to be true
      end
    end

    context 'when exception is raised' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')
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

  describe '.analyze_from_input' do
    let(:input) do
      {
        feedback_type: 'DIFFICULTY',
        rating: 4,
        feedback: '오늘 운동 좋았어요',
        would_recommend: true,
        suggestions: ['다음에 무게 올리기']
      }
    end

    context 'when LlmGateway succeeds' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: true,
          content: '{"insights": ["좋았어요"], "adaptations": ["무게 증가"], "nextWorkoutRecommendations": ["스쿼트 추가"]}',
          model: 'mock'
        })
      end

      it 'returns success with parsed response' do
        result = described_class.analyze_from_input(user: user, input: input)
        expect(result[:success]).to be true
        expect(result[:insights]).to eq(['좋았어요'])
        expect(result[:adaptations]).to eq(['무게 증가'])
        expect(result[:next_workout_recommendations]).to eq(['스쿼트 추가'])
      end
    end

    context 'when LlmGateway fails' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API error'
        })
      end

      it 'falls back to mock_input_response' do
        result = described_class.analyze_from_input(user: user, input: input)
        expect(result[:success]).to be true
        expect(result[:insights]).to be_an(Array)
      end

      context 'with high rating' do
        it 'returns positive feedback' do
          input[:rating] = 5
          result = described_class.analyze_from_input(user: user, input: input)
          expect(result[:insights]).to include('운동이 효과적이었습니다')
        end
      end

      context 'with low rating' do
        it 'returns suggestions to reduce intensity' do
          input[:rating] = 1
          result = described_class.analyze_from_input(user: user, input: input)
          expect(result[:adaptations]).to include('강도를 낮추는 것을 고려하세요')
        end
      end

      context 'with TIME feedback type' do
        it 'includes time-related recommendations' do
          input[:feedback_type] = 'TIME'
          result = described_class.analyze_from_input(user: user, input: input)
          expect(result[:next_workout_recommendations].any? { |r| r.include?('시간') }).to be true
        end
      end
    end

    context 'when exception is raised' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.analyze_from_input(user: user, input: input)
        expect(result[:success]).to be false
        expect(result[:error]).to include('피드백 분석 실패')
      end
    end
  end

  describe '.analyze_from_voice' do
    context 'when LlmGateway succeeds' do
      let(:voice_response) do
        {
          'feedback' => {
            'rating' => 4,
            'feedbackType' => 'SATISFACTION',
            'summary' => '만족스러운 운동',
            'wouldRecommend' => true
          },
          'insights' => ['좋은 운동이었습니다'],
          'adaptations' => ['강도 유지'],
          'nextWorkoutRecommendations' => ['같은 루틴 유지'],
          'interpretation' => '긍정적인 피드백'
        }
      end

      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: true,
          content: voice_response.to_json,
          model: 'mock'
        })
      end

      it 'returns success with parsed response' do
        result = described_class.analyze_from_voice(user: user, text: '오늘 운동 좋았어요')
        expect(result[:success]).to be true
        expect(result[:feedback][:rating]).to eq(4)
        expect(result[:insights]).to eq(['좋은 운동이었습니다'])
      end
    end

    context 'when LlmGateway fails (mock mode)' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API error'
        })
      end

      it 'returns mock response based on keywords' do
        result = described_class.analyze_from_voice(user: user, text: '오늘 운동 좋았어요')
        expect(result[:success]).to be true
        expect(result[:feedback]).to be_present
      end

      context 'with difficult workout feedback (Korean)' do
        it 'returns difficulty feedback' do
          result = described_class.analyze_from_voice(user: user, text: '오늘 운동 너무 힘들었어요')
          expect(result[:feedback][:rating]).to be <= 3
          expect(result[:feedback][:feedback_type]).to eq('DIFFICULTY')
          expect(result[:insights]).to include('운동이 힘들었다고 느꼈습니다')
        end
      end

      context 'with easy workout feedback (Korean)' do
        it 'returns easy feedback' do
          result = described_class.analyze_from_voice(user: user, text: '오늘 운동 쉬웠어요')
          expect(result[:feedback][:rating]).to be >= 3
          expect(result[:insights]).to include('운동이 쉬웠다고 느꼈습니다')
        end
      end

      context 'with satisfaction feedback (Korean)' do
        it 'returns satisfaction feedback' do
          result = described_class.analyze_from_voice(user: user, text: '오늘 운동 만족스러웠어요')
          expect(result[:feedback][:feedback_type]).to eq('SATISFACTION')
          expect(result[:insights]).to include('전반적으로 만족스러웠습니다')
        end
      end

      context 'with pain feedback (Korean)' do
        it 'returns pain related adaptations' do
          result = described_class.analyze_from_voice(user: user, text: '운동하다가 어깨 통증이 있어요')
          expect(result[:insights]).to include('통증이 있었습니다')
          expect(result[:adaptations]).to include('해당 부위 운동을 줄이세요')
        end
      end

      context 'with difficult workout feedback (English)' do
        it 'returns difficulty feedback' do
          result = described_class.analyze_from_voice(user: user, text: 'Workout was too hard today')
          expect(result[:feedback][:rating]).to be <= 3
          expect(result[:insights]).to include('Workout felt challenging')
        end
      end

      context 'with easy workout feedback (English)' do
        it 'returns easy feedback' do
          result = described_class.analyze_from_voice(user: user, text: 'Workout was easy')
          expect(result[:feedback][:rating]).to be >= 3
          expect(result[:insights]).to include('Workout felt easy')
        end
      end

      context 'with positive feedback (English)' do
        it 'returns positive feedback' do
          result = described_class.analyze_from_voice(user: user, text: 'Great workout today!')
          expect(result[:insights]).to include('Positive experience overall')
        end
      end

      context 'with generic text' do
        it 'returns default feedback' do
          result = described_class.analyze_from_voice(user: user, text: '그냥 보통이었어요')
          expect(result[:insights]).to include('피드백을 분석했습니다')
        end
      end
    end

    context 'when exception is raised' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.analyze_from_voice(user: user, text: '테스트')
        expect(result[:success]).to be false
        expect(result[:error]).to include('음성 피드백 분석 실패')
      end
    end
  end

  describe '#parse_input_response' do
    it 'parses valid response' do
      response = '{"insights": ["a"], "adaptations": ["b"], "nextWorkoutRecommendations": ["c"]}'
      result = service.send(:parse_input_response, response)
      expect(result[:success]).to be true
      expect(result[:insights]).to eq(['a'])
    end

    it 'handles invalid JSON' do
      result = service.send(:parse_input_response, 'invalid json')
      expect(result[:success]).to be false
    end
  end

  describe '#parse_voice_response' do
    it 'parses valid response' do
      response = '{"feedback": {"rating": 4, "feedbackType": "GENERAL", "summary": "OK", "wouldRecommend": true}, "insights": [], "adaptations": [], "nextWorkoutRecommendations": [], "interpretation": "test"}'
      result = service.send(:parse_voice_response, response)
      expect(result[:success]).to be true
      expect(result[:feedback][:rating]).to eq(4)
    end

    it 'returns retry response on invalid JSON' do
      result = service.send(:parse_voice_response, 'invalid json')
      expect(result[:success]).to be true
      expect(result[:needs_retry]).to be true
    end
  end

  describe 'with LlmGateway' do
    let(:mock_response_content) do
      {
        "feedback_type" => "DIFFICULTY",
        "rating" => 4,
        "insights" => ["좋았어요"],
        "adaptations" => ["무게 증가"],
        "next_workout_recommendations" => [],
        "affected_exercises" => [],
        "affected_muscles" => [],
        "message" => "감사합니다!"
      }
    end

    it 'uses LlmGateway for API calls' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: true,
        content: mock_response_content.to_json,
        model: 'claude-3-5-haiku-20241022'
      })

      result = service.analyze_from_text('오늘 좋았어요')
      expect(result[:success]).to be true
      expect(result[:message]).to eq('감사합니다!')

      expect(AiTrainer::LlmGateway).to have_received(:chat).with(
        hash_including(task: :feedback_analysis)
      )
    end

    it 'falls back to mock on LlmGateway failure' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: false,
        error: 'API error'
      })

      result = service.analyze_from_text('오늘 좋았어요')
      expect(result[:success]).to be true  # Falls back to mock
      expect(result[:message]).to be_present
    end
  end
end
