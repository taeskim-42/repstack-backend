# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::RoutineGenerator do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }
  let(:generator) { described_class.new(user: user) }

  describe '#initialize' do
    it 'sets default values' do
      expect(generator.user).to eq(user)
      expect(generator.level).to eq(3)
      expect(generator.condition_score).to eq(3.0)
    end

    it 'converts Sunday to Monday' do
      allow(Time).to receive(:current).and_return(Time.new(2026, 1, 25)) # Sunday
      gen = described_class.new(user: user)
      expect(gen.day_of_week).to eq(1)
    end

    it 'converts weekend days to Friday' do
      allow(Time).to receive(:current).and_return(Time.new(2026, 1, 24)) # Saturday
      gen = described_class.new(user: user)
      expect(gen.day_of_week).to eq(5)
    end

    it 'accepts explicit day_of_week' do
      gen = described_class.new(user: user, day_of_week: 3)
      expect(gen.day_of_week).to eq(3)
    end
  end

  describe '#with_condition' do
    let(:condition_inputs) do
      { sleep: 4, fatigue: 2, stress: 2, soreness: 1, motivation: 5 }
    end

    it 'sets condition inputs' do
      generator.with_condition(condition_inputs)
      expect(generator.condition_inputs).to eq(condition_inputs)
    end

    it 'calculates condition score' do
      generator.with_condition(condition_inputs)
      expect(generator.condition_score).to be > 0
    end

    it 'returns self for chaining' do
      result = generator.with_condition(condition_inputs)
      expect(result).to eq(generator)
    end
  end

  describe '#with_feedbacks' do
    let(:feedbacks) { [ double(created_at: 1.day.ago, feedback: 'test', suggestions: []) ] }

    it 'sets recent feedbacks' do
      generator.with_feedbacks(feedbacks)
      expect(generator.recent_feedbacks).to eq(feedbacks)
    end

    it 'handles nil feedbacks' do
      generator.with_feedbacks(nil)
      expect(generator.recent_feedbacks).to eq([])
    end

    it 'returns self for chaining' do
      result = generator.with_feedbacks(feedbacks)
      expect(result).to eq(generator)
    end
  end

  describe '#generate' do
    context 'without API key' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      end

      it 'returns error when API key not configured' do
        result = generator.generate
        expect(result[:success]).to be false
        expect(result[:error]).to include('ANTHROPIC_API_KEY')
      end
    end
  end

  describe '#get_grade_korean' do
    # Level 3 user (default)
    it 'returns 정상인 for levels 1-3' do
      expect(generator.send(:get_grade_korean)).to eq('정상인')
    end

    context 'with level 4 user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 4, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 건강인 for levels 4-5' do
        expect(generator.send(:get_grade_korean)).to eq('건강인')
      end
    end

    context 'with level 7 user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 7, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 운동인 for levels 6-8' do
        expect(generator.send(:get_grade_korean)).to eq('운동인')
      end
    end
  end

  describe '#get_bpm_for_level' do
    # Level 3 = intermediate tier, so returns 30-40
    it 'returns range for intermediate (level 3)' do
      result = generator.send(:get_bpm_for_level)
      expect(result).to eq('30-40')
    end

    context 'with beginner level user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 1, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 30 for beginner' do
        result = generator.send(:get_bpm_for_level)
        expect(result).to eq('30')
      end
    end

    context 'with advanced level user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 7, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns wide range for advanced' do
        result = generator.send(:get_bpm_for_level)
        expect(result).to include('자유 설정')
      end
    end
  end

  describe '#get_max_difficulty' do
    # Level 3 = intermediate tier, so returns 3
    it 'returns 3 for intermediate (level 3)' do
      result = generator.send(:get_max_difficulty)
      expect(result).to eq(3)
    end

    context 'with beginner level user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 1, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 2 for beginner' do
        result = generator.send(:get_max_difficulty)
        expect(result).to eq(2)
      end
    end

    context 'with advanced level user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 7, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 4 for advanced' do
        result = generator.send(:get_max_difficulty)
        expect(result).to eq(4)
      end
    end
  end

  describe '#format_condition_details' do
    it 'returns empty string when no condition inputs' do
      result = generator.send(:format_condition_details)
      expect(result).to eq('')
    end

    it 'formats condition inputs' do
      generator.with_condition(sleep: 4, fatigue: 2)
      result = generator.send(:format_condition_details)
      expect(result).to include('수면: 4/5')
      expect(result).to include('피로도: 2/5')
    end
  end

  describe '#format_feedback_context' do
    it 'returns empty string when no feedbacks' do
      result = generator.send(:format_feedback_context)
      expect(result).to eq('')
    end

    it 'formats feedback entries' do
      feedback = double(
        created_at: Time.current,
        feedback: '오늘 운동 좋았어요',
        suggestions: [ '무게 올리기' ]
      )
      generator.with_feedbacks([ feedback ])
      result = generator.send(:format_feedback_context)
      expect(result).to include('최근 사용자 피드백')
      expect(result).to include('오늘 운동 좋았어요')
    end
  end

  describe '#format_exercises_catalog' do
    it 'includes exercises from constants' do
      result = generator.send(:format_exercises_catalog)
      # Should include some muscle group
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end
  end

  describe '#format_training_method_details' do
    it 'formats fixed_sets_reps' do
      method = { id: 'TM01' }
      result = generator.send(:format_training_method_details, method)
      expect(result).to include('근력 훈련')
    end

    it 'formats total_reps_fill' do
      method = { id: 'TM02' }
      result = generator.send(:format_training_method_details, method)
      expect(result).to include('근지구력 훈련')
    end

    it 'formats tabata' do
      method = { id: 'TM04' }
      result = generator.send(:format_training_method_details, method)
      expect(result).to include('심폐지구력')
    end

    it 'formats explosive' do
      method = { id: 'TM05' }
      result = generator.send(:format_training_method_details, method)
      expect(result).to include('순발력')
    end

    it 'returns empty for unknown method' do
      method = { id: 'TM99' }
      result = generator.send(:format_training_method_details, method)
      expect(result).to eq('')
    end
  end

  describe '#extract_json' do
    it 'extracts JSON from markdown code blocks' do
      text = "Result:\n```json\n{\"key\": \"value\"}\n```"
      result = generator.send(:extract_json, text)
      expect(JSON.parse(result)['key']).to eq('value')
    end

    it 'extracts JSON without markdown' do
      text = 'Some text {\"key\": \"value\"} more text'
      result = generator.send(:extract_json, text)
      expect(result).to include('key')
    end
  end

  describe '#generate_routine_id' do
    it 'generates unique ID' do
      id1 = generator.send(:generate_routine_id)
      id2 = generator.send(:generate_routine_id)
      expect(id1).not_to eq(id2)
    end

    it 'includes level and day info' do
      id = generator.send(:generate_routine_id)
      expect(id).to start_with('RT-')
      expect(id).to include(generator.level.to_s)
    end
  end

  describe '#get_rom_for_factor' do
    it 'returns ROM setting for strength' do
      result = generator.send(:get_rom_for_factor, :strength)
      expect(result).not_to be_nil
    end

    it 'returns a ROM setting for power' do
      result = generator.send(:get_rom_for_factor, :power)
      expect(result).to eq(:medium)
    end

    it 'returns :full when factor not found in defaults' do
      # Use a factor that doesn't exist in the default_by_factor hash
      result = generator.send(:get_rom_for_factor, :nonexistent_factor)
      expect(result).to eq(:full)
    end
  end

  describe '#generate_with_claude' do
    let(:mock_response) do
      <<~JSON
        ```json
        {
          "exercises": [
            {
              "order": 1,
              "exercise_id": "EX_CH01",
              "exercise_name": "벤치프레스",
              "target_muscle": "chest",
              "sets": 3,
              "reps": 10
            }
          ],
          "estimated_duration_minutes": 45,
          "notes": ["오늘의 포인트"],
          "variation_seed": "테스트 루틴"
        }
        ```
      JSON
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
    end

    it 'generates routine when API is configured' do
      allow(generator).to receive(:call_claude_api).and_return(mock_response)

      result = generator.generate
      expect(result[:routine_id]).to start_with('RT-')
      expect(result[:exercises]).to be_an(Array)
    end

    it 'handles API errors gracefully' do
      allow(generator).to receive(:call_claude_api).and_raise(StandardError, 'Network error')

      result = generator.generate
      expect(result[:success]).to be false
      expect(result[:error]).to include('루틴 생성 실패')
    end
  end

  describe '#build_prompt' do
    it 'includes user information' do
      prompt = generator.send(:build_prompt)
      expect(prompt).to include('레벨: 3/8')
      expect(prompt).to include('175')
    end

    it 'includes training method' do
      prompt = generator.send(:build_prompt)
      expect(prompt).to include('훈련방법')
    end

    it 'includes condition score' do
      prompt = generator.send(:build_prompt)
      expect(prompt).to include('컨디션 점수')
    end

    it 'includes weight calculations' do
      prompt = generator.send(:build_prompt)
      expect(prompt).to include('벤치프레스')
      expect(prompt).to include('스쿼트')
      expect(prompt).to include('데드리프트')
    end

    it 'includes random seed for variation' do
      prompt = generator.send(:build_prompt)
      expect(prompt).to include('랜덤 시드')
    end

    context 'with condition inputs' do
      before do
        generator.with_condition(sleep: 4, fatigue: 2, stress: 3)
      end

      it 'includes condition details' do
        prompt = generator.send(:build_prompt)
        expect(prompt).to include('수면: 4/5')
        expect(prompt).to include('피로도: 2/5')
        expect(prompt).to include('스트레스: 3/5')
      end
    end

    context 'with feedbacks' do
      let(:feedback) do
        double(
          created_at: Time.current,
          feedback: '운동이 좋았어요',
          suggestions: [ '무게 올리기' ]
        )
      end

      before do
        generator.with_feedbacks([ feedback ])
      end

      it 'includes feedback context' do
        prompt = generator.send(:build_prompt)
        expect(prompt).to include('최근 사용자 피드백')
      end
    end

    context 'without user weight' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: nil) }

      it 'handles nil weight gracefully' do
        prompt = generator.send(:build_prompt)
        expect(prompt).to include('미입력')
      end
    end
  end

  describe '#parse_claude_response' do
    let(:valid_response) do
      <<~JSON
        ```json
        {
          "exercises": [
            {
              "order": 1,
              "exercise_id": "EX_CH01",
              "exercise_name": "벤치프레스",
              "exercise_name_english": "Bench Press",
              "target_muscle": "chest",
              "target_muscle_korean": "가슴",
              "equipment": "barbell",
              "sets": 3,
              "reps": 10,
              "bpm": 30,
              "rest_seconds": 60,
              "rest_type": "time_based",
              "range_of_motion": "full",
              "target_weight_kg": 60,
              "instructions": "벤치에 누워서 수행"
            }
          ],
          "estimated_duration_minutes": 45,
          "notes": ["오늘의 포인트", "주의사항"],
          "variation_seed": "상체 근력 중심 루틴"
        }
        ```
      JSON
    end

    it 'parses valid response' do
      result = generator.send(:parse_claude_response, valid_response)
      expect(result[:routine_id]).to start_with('RT-')
      expect(result[:exercises].length).to eq(1)
      expect(result[:exercises].first['exercise_name']).to eq('벤치프레스')
    end

    it 'includes metadata' do
      result = generator.send(:parse_claude_response, valid_response)
      expect(result[:user_level]).to eq(3)
      expect(result[:tier]).to be_present
      expect(result[:condition]).to be_a(Hash)
    end

    it 'sets defaults for missing fields' do
      minimal_response = '{"exercises": []}'
      result = generator.send(:parse_claude_response, minimal_response)
      expect(result[:estimated_duration_minutes]).to eq(45)
      expect(result[:notes]).to eq([])
    end
  end

  describe '#call_claude_api' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
    end

    it 'raises error on non-200 response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 500, body: 'Internal Server Error')

      expect { generator.send(:call_claude_api, 'test prompt') }
        .to raise_error(RuntimeError, /Claude API returned 500/)
    end

    it 'returns text content on success' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: { content: [ { text: '{"exercises": []}' } ] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = generator.send(:call_claude_api, 'test prompt')
      expect(result).to eq('{"exercises": []}')
    end
  end

  describe '#api_configured?' do
    context 'with API key' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
      end

      it 'returns true' do
        expect(generator.send(:api_configured?)).to be true
      end
    end

    context 'without API key' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      end

      it 'returns false' do
        expect(generator.send(:api_configured?)).to be false
      end
    end
  end

  describe '#extract_json edge cases' do
    it 'handles JSON without markdown' do
      text = 'Here is the response: {"key": "value"} end'
      result = generator.send(:extract_json, text)
      expect(result).to eq('{"key": "value"}')
    end

    it 'returns text as-is when no JSON found' do
      text = 'No JSON here'
      result = generator.send(:extract_json, text)
      expect(result).to eq('No JSON here')
    end
  end

  describe 'condition score integration' do
    it 'adjusts for poor condition' do
      generator.with_condition(sleep: 1, fatigue: 5, stress: 5, soreness: 5, motivation: 1)
      expect(generator.condition_score).to be < 2.5
      expect(generator.adjustment[:volume_modifier]).to be < 1.0
    end

    it 'adjusts for excellent condition' do
      generator.with_condition(sleep: 5, fatigue: 1, stress: 1, soreness: 1, motivation: 5)
      expect(generator.condition_score).to be > 3.5
    end
  end

  describe 'level-based configurations' do
    context 'with level 8 user (max)' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 8, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns correct grade' do
        expect(generator.send(:get_grade_korean)).to eq('운동인')
      end

      it 'allows max difficulty' do
        expect(generator.send(:get_max_difficulty)).to eq(4)
      end
    end

    context 'with level 2 user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 2, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns correct grade' do
        expect(generator.send(:get_grade_korean)).to eq('정상인')
      end

      it 'limits difficulty' do
        expect(generator.send(:get_max_difficulty)).to eq(2)
      end
    end

    context 'with level 5 user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 5, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 건강인 grade' do
        expect(generator.send(:get_grade_korean)).to eq('건강인')
      end

      it 'allows intermediate difficulty' do
        expect(generator.send(:get_max_difficulty)).to eq(3)
      end
    end

    context 'with level 6 user' do
      let!(:user_profile) { create(:user_profile, user: user, numeric_level: 6, height: 175, weight: 70) }
      let(:generator) { described_class.new(user: user.reload) }

      it 'returns 운동인 grade' do
        expect(generator.send(:get_grade_korean)).to eq('운동인')
      end

      it 'returns advanced BPM range' do
        result = generator.send(:get_bpm_for_level)
        expect(result).to include('자유 설정')
      end
    end
  end

  describe 'format_feedback_context with multiple feedbacks' do
    it 'limits to first 5 feedbacks' do
      feedbacks = 10.times.map do |i|
        double(
          created_at: i.days.ago,
          feedback: "Feedback #{i}",
          suggestions: [ "Suggestion #{i}" ]
        )
      end
      generator.with_feedbacks(feedbacks)
      result = generator.send(:format_feedback_context)
      # Should only include first 5
      expect(result).to include('Feedback 0')
      expect(result).to include('Feedback 4')
      expect(result).not_to include('Feedback 5')
    end

    it 'handles suggestions as string' do
      feedback = double(
        created_at: Time.current,
        feedback: 'Test feedback',
        suggestions: 'String suggestion'
      )
      generator.with_feedbacks([ feedback ])
      result = generator.send(:format_feedback_context)
      expect(result).to include('String suggestion')
    end
  end

  describe 'format_training_method_details' do
    it 'formats TM03 max_sets_at_fixed_reps' do
      method = { id: 'TM03' }
      result = generator.send(:format_training_method_details, method)
      expect(result).to include('지속력 훈련')
    end
  end
end
