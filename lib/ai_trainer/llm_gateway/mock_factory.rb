# frozen_string_literal: true

module AiTrainer
  module LlmGatewayMockFactory
    private

    # Mock response for development without API key
    def mock_response(task, tools: nil)
      Rails.logger.info("[LlmGateway] Mock response for #{task} (API not configured)")

      if tools.present?
        return {
          success: true,
          content: "테스트 응답입니다.",
          model: "mock",
          stop_reason: "end_turn",
          usage: { input_tokens: 0, output_tokens: 0 }
        }
      end

      content = case task
      when :routine_generation then mock_routine_json
      when :condition_check then mock_condition_json
      when :feedback_analysis then mock_feedback_json
      when :level_assessment then mock_assessment_response
      when :intent_classification then "general_chat"
      when :voice_normalization then '{"exercise":"벤치프레스","weight":60,"reps":10,"sets":null,"intent":"record_set"}'
      else "이것은 테스트 응답입니다. API 키가 설정되면 실제 AI 응답을 받을 수 있어요! 💪"
      end

      {
        success: true,
        content: content,
        model: "mock",
        stop_reason: "end_turn",
        usage: { input_tokens: 0, output_tokens: 0 }
      }
    end

    def mock_routine_json
      {
        exercises: [
          {
            order: 1,
            exercise_id: "EX_CH01",
            exercise_name: "벤치프레스",
            exercise_name_english: "Bench Press",
            target_muscle: "chest",
            target_muscle_korean: "가슴",
            equipment: "barbell",
            sets: 4,
            reps: 10,
            bpm: 30,
            rest_seconds: 90,
            rest_type: "time_based",
            range_of_motion: "full",
            target_weight_kg: 60,
            weight_description: "목표 중량: 60kg",
            instructions: "가슴을 펴고 바를 천천히 내린 후 폭발적으로 밀어올립니다."
          }
        ],
        estimated_duration_minutes: 45,
        notes: [ "오늘은 가슴 중심 운동입니다", "마지막 세트는 힘들어도 포기하지 마세요" ],
        variation_seed: "가슴 집중 루틴"
      }.to_json
    end

    def mock_condition_json
      {
        score: 80,
        status: "good",
        message: "컨디션이 좋네요! 오늘 운동하기 딱 좋은 상태입니다.",
        recommendations: [ "충분한 수분 섭취를 유지하세요" ],
        adaptations: []
      }.to_json
    end

    def mock_feedback_json
      {
        analysis: "운동을 잘 수행하셨네요!",
        suggestions: [ "다음에는 무게를 조금 올려보세요" ],
        encouragement: "꾸준히 잘하고 계세요! 💪"
      }.to_json
    end

    def mock_assessment_response
      # Return JSON format so parse_response can handle it properly
      {
        message: "좋아요! 운동 경험이 어느 정도 되시나요?",
        next_state: "asking_experience",
        collected_data: {},
        is_complete: false,
        assessment: nil
      }.to_json
    end
  end
end
