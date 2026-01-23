# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::ConditionService do
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
        result = described_class.analyze_from_text(user: user, text: '오늘 컨디션 좋아요')
        expect(result[:success]).to be true
      end

      it 'returns default score from mock' do
        result = described_class.analyze_from_text(user: user, text: '오늘 컨디션 좋아요')
        expect(result[:score]).to eq(70)
      end

      it 'returns status' do
        result = described_class.analyze_from_text(user: user, text: '오늘 컨디션 좋아요')
        expect(result[:status]).to eq('good')
      end

      it 'returns message' do
        result = described_class.analyze_from_text(user: user, text: '오늘 컨디션 좋아요')
        expect(result[:message]).to be_present
      end

      it 'returns adaptations' do
        result = described_class.analyze_from_text(user: user, text: '오늘 컨디션 좋아요')
        expect(result[:adaptations]).to be_an(Array)
      end

      it 'returns recommendations' do
        result = described_class.analyze_from_text(user: user, text: '오늘 컨디션 좋아요')
        expect(result[:recommendations]).to be_an(Array)
      end
    end

    context 'when exception is raised' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.analyze_from_text(user: user, text: '테스트')
        expect(result[:success]).to be false
        expect(result[:error]).to include('컨디션 분석 실패')
      end
    end
  end

  describe '#extract_json' do
    it 'extracts JSON from markdown code blocks' do
      text = "결과:\n```json\n{\"score\": 80}\n```"
      result = service.send(:extract_json, text)
      expect(JSON.parse(result)['score']).to eq(80)
    end

    it 'extracts JSON without markdown' do
      text = "분석 결과는 {\"score\": 75} 입니다"
      result = service.send(:extract_json, text)
      expect(JSON.parse(result)['score']).to eq(75)
    end
  end

  describe '#save_condition_log' do
    let(:parsed_condition) do
      {
        'energy_level' => 4,
        'stress_level' => 2,
        'sleep_quality' => 4,
        'motivation' => 3,
        'soreness' => 1
      }
    end

    it 'creates condition log record' do
      expect do
        service.send(:save_condition_log, parsed_condition)
      end.to change { user.condition_logs.count }.by(1)
    end

    it 'sets correct values' do
      service.send(:save_condition_log, parsed_condition)
      log = user.condition_logs.last

      expect(log.energy_level).to eq(4)
      expect(log.stress_level).to eq(2)
      expect(log.sleep_quality).to eq(4)
      expect(log.motivation).to eq(3)
    end

    it 'handles nil condition gracefully' do
      expect do
        service.send(:save_condition_log, nil)
      end.not_to change { user.condition_logs.count }
    end

    it 'handles duplicate date gracefully' do
      # Create first log
      service.send(:save_condition_log, parsed_condition)

      # Second log on same date should not raise
      expect do
        service.send(:save_condition_log, parsed_condition)
      end.not_to raise_error
    end
  end

  describe '#build_prompt' do
    it 'includes user text' do
      prompt = service.send(:build_prompt, '오늘 피곤해요')
      expect(prompt).to include('오늘 피곤해요')
    end

    it 'includes condition fields' do
      prompt = service.send(:build_prompt, '테스트')
      expect(prompt).to include('energy_level')
      expect(prompt).to include('stress_level')
      expect(prompt).to include('sleep_quality')
    end
  end

  describe '#parse_response' do
    let(:valid_response) do
      <<~JSON
        ```json
        {
          "parsed_condition": {
            "energy_level": 4,
            "stress_level": 2,
            "sleep_quality": 4,
            "motivation": 4,
            "soreness": 1
          },
          "overall_score": 80,
          "status": "good",
          "message": "컨디션 좋아요!",
          "adaptations": ["평소 강도 유지"],
          "recommendations": ["수분 섭취"]
        }
        ```
      JSON
    end

    it 'parses valid response' do
      result = service.send(:parse_response, valid_response, '테스트')
      expect(result[:success]).to be true
      expect(result[:score]).to eq(80)
      expect(result[:status]).to eq('good')
    end

    it 'saves condition log' do
      expect { service.send(:parse_response, valid_response, '테스트') }
        .to change { user.condition_logs.count }.by(1)
    end

    it 'returns error on invalid JSON' do
      result = service.send(:parse_response, 'invalid json', '테스트')
      expect(result[:success]).to be false
      expect(result[:error]).to include('파싱 실패')
    end

    it 'handles missing optional fields' do
      minimal_response = '{"parsed_condition": {}, "overall_score": 70, "status": "good", "message": "OK"}'
      result = service.send(:parse_response, minimal_response, '테스트')
      expect(result[:adaptations]).to eq([])
      expect(result[:recommendations]).to eq([])
    end
  end

  describe '#extract_json edge cases' do
    it 'handles markdown without json tag' do
      text = "Here:\n```\n{\"key\": \"value\"}\n```"
      result = service.send(:extract_json, text)
      expect(JSON.parse(result)['key']).to eq('value')
    end

    it 'returns text as-is when no JSON found' do
      text = 'No JSON here'
      result = service.send(:extract_json, text)
      expect(result).to eq('No JSON here')
    end
  end

  describe '#mock_response' do
    it 'returns complete response structure' do
      result = service.send(:mock_response)
      expect(result[:success]).to be true
      expect(result[:score]).to eq(70)
      expect(result[:status]).to eq('good')
      expect(result[:message]).to be_present
      expect(result[:adaptations]).to be_an(Array)
      expect(result[:recommendations]).to be_an(Array)
    end
  end

  describe 'with LlmGateway' do
    let(:mock_response_content) do
      {
        "parsed_condition" => {"energy_level" => 4, "stress_level" => 2, "sleep_quality" => 4, "motivation" => 4, "soreness" => 1},
        "overall_score" => 80,
        "status" => "good",
        "message" => "좋아요!",
        "adaptations" => [],
        "recommendations" => []
      }
    end

    it 'uses LlmGateway for API calls' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: true,
        content: mock_response_content.to_json,
        model: 'claude-3-5-haiku-20241022'
      })

      result = service.analyze_from_text('오늘 좋아요')
      expect(result[:success]).to be true
      expect(result[:score]).to eq(80)

      expect(AiTrainer::LlmGateway).to have_received(:chat).with(
        hash_including(task: :condition_check)
      )
    end

    it 'falls back to mock on LlmGateway failure' do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: false,
        error: 'API error'
      })

      result = service.analyze_from_text('오늘 좋아요')
      expect(result[:success]).to be true  # Falls back to mock
      expect(result[:score]).to eq(70)     # Default mock score
    end
  end
end
