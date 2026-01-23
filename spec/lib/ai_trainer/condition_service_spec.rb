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

  describe '.analyze_from_input' do
    let(:input) do
      {
        energy_level: 4,
        stress_level: 2,
        sleep_quality: 4,
        motivation: 3,
        available_time: 60,
        soreness: { shoulder: 2 },
        notes: '어깨가 약간 뻐근'
      }
    end

    context 'when LLM responds successfully' do
      let(:llm_response) do
        {
          success: true,
          content: {
            adaptations: ['어깨 운동 강도 낮추기'],
            intensityModifier: 0.9,
            durationModifier: 1.0,
            exerciseModifications: ['푸시업 대신 벤치프레스'],
            restRecommendations: ['어깨 스트레칭 추가']
          }.to_json
        }
      end

      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return(llm_response)
      end

      it 'returns parsed response' do
        result = described_class.analyze_from_input(user: user, input: input)
        expect(result[:success]).to be true
        expect(result[:adaptations]).to include('어깨 운동 강도 낮추기')
        expect(result[:intensity_modifier]).to eq(0.9)
      end
    end

    context 'when LLM fails (falls back to mock)' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API error'
        })
      end

      it 'returns mock response' do
        result = described_class.analyze_from_input(user: user, input: input)
        expect(result[:success]).to be true
        expect(result[:adaptations]).to be_an(Array)
        expect(result[:intensity_modifier]).to be_a(Float)
      end
    end

    context 'when exception is raised' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.analyze_from_input(user: user, input: input)
        expect(result[:success]).to be false
        expect(result[:error]).to include('컨디션 분석 실패')
      end
    end
  end

  describe '.analyze_from_voice' do
    context 'when LLM responds successfully' do
      let(:llm_response) do
        {
          success: true,
          content: {
            condition: {
              energyLevel: 3,
              stressLevel: 4,
              sleepQuality: 3,
              motivation: 3,
              soreness: { back: 2 },
              availableTime: 45,
              notes: '허리 조심'
            },
            adaptations: ['허리 무리하지 않기'],
            intensityModifier: 0.8,
            durationModifier: 0.9,
            exerciseModifications: ['데드리프트 제외'],
            restRecommendations: ['세트 사이 휴식 늘리기'],
            interpretation: '허리 통증으로 인해 강도 조절 필요'
          }.to_json
        }
      end

      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return(llm_response)
      end

      it 'returns parsed condition and adaptations' do
        result = described_class.analyze_from_voice(user: user, text: '오늘 허리가 좀 아파요')
        expect(result[:success]).to be true
        expect(result[:condition][:stress_level]).to eq(4)
        expect(result[:adaptations]).to include('허리 무리하지 않기')
        expect(result[:interpretation]).to include('허리')
      end
    end

    context 'when LLM fails (falls back to mock)' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API error'
        })
      end

      it 'detects tired condition (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '오늘 너무 피곤해요')
        expect(result[:success]).to be true
        expect(result[:condition][:energy_level]).to eq(2)
        expect(result[:adaptations]).to include('운동 강도를 낮추세요')
      end

      it 'detects good condition (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '컨디션 좋아요!')
        expect(result[:success]).to be true
        expect(result[:condition][:energy_level]).to eq(4)
      end

      it 'detects excellent condition (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '오늘 컨디션 최고예요!')
        expect(result[:success]).to be true
        expect(result[:condition][:energy_level]).to eq(5)
      end

      it 'detects stress (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '스트레스 받아서 운동하고 싶어요')
        expect(result[:success]).to be true
        expect(result[:condition][:stress_level]).to eq(4)
        expect(result[:condition][:motivation]).to eq(4)
        expect(result[:adaptations]).to include('스트레스 해소 운동을 포함하세요')
      end

      it 'detects poor sleep (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '어제 잠을 못 잤어요')
        expect(result[:success]).to be true
        expect(result[:condition][:sleep_quality]).to eq(2)
        expect(result[:adaptations]).to include('운동 시간을 줄이세요')
      end

      it 'detects tired condition (English)' do
        result = described_class.analyze_from_voice(user: user, text: "I'm so tired today")
        expect(result[:success]).to be true
        expect(result[:condition][:energy_level]).to eq(2)
      end

      it 'detects good condition (English)' do
        result = described_class.analyze_from_voice(user: user, text: "Feeling great today!")
        expect(result[:success]).to be true
        expect(result[:condition][:energy_level]).to eq(4)
      end

      it 'detects shoulder soreness (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '어깨가 아파요')
        expect(result[:success]).to be true
        expect(result[:condition][:soreness]).to eq({ 'shoulder' => 3 })
        expect(result[:exercise_modifications]).to include('어깨 운동 제외')
      end

      it 'detects back soreness (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '허리가 아파요')
        expect(result[:success]).to be true
        expect(result[:condition][:soreness]).to eq({ 'back' => 3 })
      end

      it 'detects leg soreness (Korean)' do
        result = described_class.analyze_from_voice(user: user, text: '다리가 아파요')
        expect(result[:success]).to be true
        expect(result[:condition][:soreness]).to eq({ 'legs' => 3 })
      end

      it 'returns default adaptations for normal condition' do
        result = described_class.analyze_from_voice(user: user, text: '보통이에요')
        expect(result[:success]).to be true
        expect(result[:adaptations]).to include('오늘 컨디션에 맞는 운동을 추천합니다')
      end
    end

    context 'when exception is raised' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_raise(StandardError, 'Network error')
      end

      it 'returns error response' do
        result = described_class.analyze_from_voice(user: user, text: '테스트')
        expect(result[:success]).to be false
        expect(result[:error]).to include('음성 컨디션 분석 실패')
      end
    end
  end

  describe '#build_input_prompt' do
    it 'includes condition values' do
      input = { energy_level: 4, stress_level: 2, sleep_quality: 3, motivation: 4, available_time: 45 }
      prompt = service.send(:build_input_prompt, input)
      expect(prompt).to include('Energy Level: 4/5')
      expect(prompt).to include('Stress Level: 2/5')
      expect(prompt).to include('Available Time: 45 minutes')
    end

    it 'includes soreness when present' do
      input = { energy_level: 3, soreness: { shoulder: 2 } }
      prompt = service.send(:build_input_prompt, input)
      expect(prompt).to include('shoulder')
    end

    it 'handles nil soreness' do
      input = { energy_level: 3, soreness: nil }
      prompt = service.send(:build_input_prompt, input)
      expect(prompt).to include('None reported')
    end
  end

  describe '#parse_input_response' do
    let(:valid_response) do
      <<~JSON
        ```json
        {
          "adaptations": ["강도 조절"],
          "intensityModifier": 0.85,
          "durationModifier": 0.9,
          "exerciseModifications": ["변형 운동"],
          "restRecommendations": ["휴식 늘리기"]
        }
        ```
      JSON
    end

    it 'parses valid response' do
      result = service.send(:parse_input_response, valid_response)
      expect(result[:success]).to be true
      expect(result[:adaptations]).to eq(['강도 조절'])
      expect(result[:intensity_modifier]).to eq(0.85)
      expect(result[:duration_modifier]).to eq(0.9)
    end

    it 'returns error on invalid JSON' do
      result = service.send(:parse_input_response, 'invalid json')
      expect(result[:success]).to be false
      expect(result[:error]).to include('파싱 실패')
    end

    it 'handles missing optional fields' do
      minimal = '{"adaptations": []}'
      result = service.send(:parse_input_response, minimal)
      expect(result[:intensity_modifier]).to eq(1.0)
      expect(result[:duration_modifier]).to eq(1.0)
    end
  end

  describe '#mock_input_response' do
    it 'reduces intensity for low energy' do
      input = { energy_level: 1, stress_level: 3, sleep_quality: 3 }
      result = service.send(:mock_input_response, input)
      expect(result[:adaptations]).to include('운동 강도를 낮추세요')
      expect(result[:intensity_modifier]).to be < 1.0
    end

    it 'adds stress relief for high stress' do
      input = { energy_level: 3, stress_level: 5, sleep_quality: 3 }
      result = service.send(:mock_input_response, input)
      expect(result[:adaptations]).to include('스트레스 해소 운동을 포함하세요')
      expect(result[:rest_recommendations]).to include('세트 사이 휴식을 늘리세요')
    end

    it 'reduces duration for poor sleep' do
      input = { energy_level: 3, stress_level: 3, sleep_quality: 1 }
      result = service.send(:mock_input_response, input)
      expect(result[:adaptations]).to include('운동 시간을 줄이세요')
    end

    it 'uses default when all conditions are good' do
      input = { energy_level: 4, stress_level: 2, sleep_quality: 4 }
      result = service.send(:mock_input_response, input)
      expect(result[:adaptations]).to include('평소 강도로 운동 가능')
    end

    it 'handles nil values' do
      input = {}
      result = service.send(:mock_input_response, input)
      expect(result[:success]).to be true
      expect(result[:adaptations]).to be_an(Array)
    end
  end

  describe '#build_voice_prompt' do
    it 'includes user text' do
      prompt = service.send(:build_voice_prompt, '오늘 피곤해요')
      expect(prompt).to include('오늘 피곤해요')
    end

    it 'includes JSON format instructions' do
      prompt = service.send(:build_voice_prompt, 'test')
      expect(prompt).to include('energyLevel')
      expect(prompt).to include('adaptations')
    end
  end

  describe '#parse_voice_response' do
    let(:valid_response) do
      <<~JSON
        ```json
        {
          "condition": {
            "energyLevel": 4,
            "stressLevel": 2,
            "sleepQuality": 4,
            "motivation": 5,
            "soreness": {"shoulder": 2},
            "availableTime": 90,
            "notes": "어깨 조심"
          },
          "adaptations": ["어깨 운동 제외"],
          "intensityModifier": 0.9,
          "durationModifier": 1.1,
          "exerciseModifications": ["푸시업 변형"],
          "restRecommendations": ["스트레칭 추가"],
          "interpretation": "전반적으로 좋지만 어깨 주의"
        }
        ```
      JSON
    end

    it 'parses valid response' do
      result = service.send(:parse_voice_response, valid_response)
      expect(result[:success]).to be true
      expect(result[:condition][:energy_level]).to eq(4)
      expect(result[:condition][:soreness]).to eq({ 'shoulder' => 2 })
      expect(result[:interpretation]).to include('어깨')
    end

    it 'returns error on invalid JSON' do
      result = service.send(:parse_voice_response, 'invalid json')
      expect(result[:success]).to be false
      expect(result[:error]).to include('파싱 실패')
    end

    it 'handles missing optional fields' do
      minimal = '{"condition": {}, "adaptations": []}'
      result = service.send(:parse_voice_response, minimal)
      expect(result[:condition][:energy_level]).to eq(3)
      expect(result[:condition][:available_time]).to eq(60)
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
