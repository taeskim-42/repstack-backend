# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Generates workout routines using Claude API with variable catalog
  # Creates infinite variations based on fitness factors, level, and condition
  class RoutineGenerator
    include Constants

    API_URL = "https://api.anthropic.com/v1/messages"
    MODEL = "claude-sonnet-4-20250514"
    MAX_TOKENS = 4096

    attr_reader :user, :level, :day_of_week, :condition_score, :adjustment, :condition_inputs, :recent_feedbacks

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || user.user_profile&.level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0 # Sunday -> Monday
      @day_of_week = 5 if @day_of_week > 5 # Weekend -> Friday
      @condition_score = 3.0
      @adjustment = Constants::CONDITION_ADJUSTMENTS[:good]
      @condition_inputs = {}
      @recent_feedbacks = []
    end

    # Set condition from user input
    def with_condition(condition_inputs)
      @condition_inputs = condition_inputs
      @condition_score = Constants.calculate_condition_score(condition_inputs)
      @adjustment = Constants.adjustment_for_condition_score(@condition_score)
      self
    end

    # Set recent feedbacks for personalization
    def with_feedbacks(feedbacks)
      @recent_feedbacks = feedbacks || []
      self
    end

    # Generate a complete routine using Claude API
    def generate
      if api_configured?
        generate_with_claude
      else
        Rails.logger.warn("RoutineGenerator: API key not configured, returning error")
        { success: false, error: "ANTHROPIC_API_KEY가 설정되지 않았습니다." }
      end
    end

    private

    def api_configured?
      ENV["ANTHROPIC_API_KEY"].present?
    end

    def generate_with_claude
      prompt = build_prompt
      response = call_claude_api(prompt)
      parse_claude_response(response)
    rescue StandardError => e
      Rails.logger.error("RoutineGenerator Claude API error: #{e.message}")
      { success: false, error: "루틴 생성 실패: #{e.message}" }
    end

    def build_prompt
      fitness_factor = Constants.fitness_factor_for_day(@day_of_week)
      factor_info = Constants::FITNESS_FACTORS[fitness_factor]
      training_method = Constants::TRAINING_METHODS[Constants.training_method_for_factor(fitness_factor)]
      height = @user.user_profile&.height || 170
      weight = @user.user_profile&.weight

      <<~PROMPT
        당신은 전문 피트니스 트레이너입니다. 아래 정보를 바탕으로 오늘의 운동 루틴을 생성하세요.
        매번 다른 운동 조합과 변수를 사용하여 사용자가 지루함을 느끼지 않도록 하세요.

        ## 사용자 정보
        - 레벨: #{@level}/8 (#{Constants.tier_for_level(@level)})
        - 등급: #{get_grade_korean}
        - 키: #{height}cm
        - 체중: #{weight || '미입력'}kg

        ## 오늘의 운동
        - 요일: #{Constants::WEEKLY_STRUCTURE[@day_of_week][:korean]} (Day #{@day_of_week})
        - 체력요인: #{factor_info[:korean]} (#{fitness_factor})
        - 훈련방법: #{training_method[:korean]}
        - 훈련방법 설명: #{training_method[:description]}

        ## 사용자 컨디션
        - 컨디션 점수: #{@condition_score.round(1)}/5.0 (#{@adjustment[:korean]})
        - 볼륨 조정: #{(@adjustment[:volume_modifier] * 100).round}%
        - 강도 조정: #{(@adjustment[:intensity_modifier] * 100).round}%
        #{format_condition_details}
        #{format_feedback_context}

        ## 운동 변수 카탈로그

        ### 사용 가능한 운동 목록
        #{format_exercises_catalog}

        ### 중량 계산 공식 (바벨 운동)
        - 벤치프레스: (키-100) × #{Constants.weight_multiplier_for_level(@level)} = #{((height - 100) * Constants.weight_multiplier_for_level(@level)).round(1)}kg
        - 스쿼트: (키-100+20) × #{Constants.weight_multiplier_for_level(@level)} = #{((height - 80) * Constants.weight_multiplier_for_level(@level)).round(1)}kg
        - 데드리프트: (키-100+40) × #{Constants.weight_multiplier_for_level(@level)} = #{((height - 60) * Constants.weight_multiplier_for_level(@level)).round(1)}kg

        ### 훈련 변수
        - BPM: #{get_bpm_for_level} (메트로놈 템포)
        - 가동범위: #{get_rom_for_factor(fitness_factor)}
        - 휴식: #{factor_info[:typical_rest]}초 (시간 기반) 또는 심박수 회복 후
        #{format_training_method_details(training_method)}

        ## 규칙
        1. 오늘의 체력요인(#{factor_info[:korean]})에 맞는 훈련방법을 적용하세요
        2. 사용자 레벨에 맞는 난이도의 운동을 선택하세요 (레벨 #{@level}이면 difficulty #{get_max_difficulty} 이하)
        3. 컨디션에 따라 볼륨과 강도를 조절하세요
        4. 매번 다른 조합으로 루틴을 생성하여 지루함을 방지하세요
        5. 가슴, 등, 하체, 코어를 균형있게 포함하세요 (4-5개 운동)
        6. 랜덤 시드: #{SecureRandom.hex(8)} (이 값을 참고하여 다양한 변이를 만드세요)

        ## 출력 형식
        반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트를 추가하지 마세요:
        ```json
        {
          "exercises": [
            {
              "order": 1,
              "exercise_id": "EX_XX00",
              "exercise_name": "운동명",
              "exercise_name_english": "Exercise Name",
              "target_muscle": "chest|back|legs|shoulders|arms|core|cardio",
              "target_muscle_korean": "타겟 근육 한글",
              "equipment": "none|barbell|dumbbell|cable|machine|shark_rack|pull_up_bar",
              "sets": 3,
              "reps": 10,
              "target_total_reps": null,
              "bpm": 30,
              "rest_seconds": 60,
              "rest_type": "time_based|heart_rate_based",
              "heart_rate_threshold": null,
              "range_of_motion": "full|medium|short",
              "target_weight_kg": null,
              "weight_description": "체중|10회 가능한 무게|목표 중량: XXkg",
              "work_seconds": null,
              "rounds": null,
              "instructions": "운동 수행 방법 및 주의사항"
            }
          ],
          "estimated_duration_minutes": 45,
          "notes": ["오늘의 포인트", "주의사항"],
          "variation_seed": "이 루틴의 특징을 한 문장으로"
        }
        ```
      PROMPT
    end

    def call_claude_api(prompt)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
      request["anthropic-version"] = "2023-06-01"

      request.body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [ { role: "user", content: prompt } ]
      }.to_json

      response = http.request(request)

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        data.dig("content", 0, "text")
      else
        Rails.logger.error("Claude API error: #{response.code} - #{response.body}")
        raise "Claude API returned #{response.code}"
      end
    end

    def parse_claude_response(response_text)
      json_str = extract_json(response_text)
      data = JSON.parse(json_str)

      fitness_factor = Constants.fitness_factor_for_day(@day_of_week)
      training_method = Constants.training_method_for_factor(fitness_factor)

      {
        routine_id: generate_routine_id,
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        day_of_week: Constants::WEEKLY_STRUCTURE[@day_of_week][:day],
        day_korean: Constants::WEEKLY_STRUCTURE[@day_of_week][:korean],
        fitness_factor: fitness_factor,
        fitness_factor_korean: Constants::FITNESS_FACTORS[fitness_factor][:korean],
        training_method: training_method,
        training_method_info: Constants::TRAINING_METHODS[training_method],
        condition: {
          score: @condition_score.round(2),
          status: @adjustment[:korean],
          volume_modifier: @adjustment[:volume_modifier],
          intensity_modifier: @adjustment[:intensity_modifier]
        },
        estimated_duration_minutes: data["estimated_duration_minutes"] || 45,
        exercises: data["exercises"] || [],
        notes: data["notes"] || [],
        variation_seed: data["variation_seed"]
      }
    end

    def extract_json(text)
      if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif text.include?("{")
        start_idx = text.index("{")
        end_idx = text.rindex("}")
        text[start_idx..end_idx] if start_idx && end_idx
      else
        text
      end
    end

    def generate_routine_id
      "RT-#{@level}-#{@day_of_week}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end

    # Helper methods for prompt building
    def get_grade_korean
      case @level
      when 1..3 then "정상인"
      when 4..5 then "건강인"
      when 6..8 then "운동인"
      else "정상인"
      end
    end

    def get_bpm_for_level
      case Constants.tier_for_level(@level)
      when "beginner" then "30"
      when "intermediate" then "30-40"
      when "advanced" then "20-60 (자유 설정)"
      else "30"
      end
    end

    def get_rom_for_factor(factor)
      Constants::TRAINING_VARIABLES.dig(:range_of_motion, :default_by_factor, factor) || :full
    end

    def get_max_difficulty
      case Constants.tier_for_level(@level)
      when "beginner" then 2
      when "intermediate" then 3
      else 4
      end
    end

    def format_condition_details
      return "" if @condition_inputs.empty?

      details = []
      details << "- 수면: #{@condition_inputs[:sleep]}/5" if @condition_inputs[:sleep]
      details << "- 피로도: #{@condition_inputs[:fatigue]}/5" if @condition_inputs[:fatigue]
      details << "- 스트레스: #{@condition_inputs[:stress]}/5" if @condition_inputs[:stress]
      details << "- 근육통: #{@condition_inputs[:soreness]}/5" if @condition_inputs[:soreness]
      details << "- 의욕: #{@condition_inputs[:motivation]}/5" if @condition_inputs[:motivation]
      details.join("\n")
    end

    def format_feedback_context
      return "" if @recent_feedbacks.blank?

      feedback_lines = @recent_feedbacks.first(5).map do |fb|
        suggestions = fb.suggestions.is_a?(Array) ? fb.suggestions.join(", ") : fb.suggestions.to_s
        "- #{fb.created_at.strftime('%Y-%m-%d')}: #{fb.feedback.truncate(100)}\n  → 적용사항: #{suggestions}"
      end

      <<~FEEDBACK

        ## 최근 사용자 피드백 (다음 루틴에 반영 필요)
        #{feedback_lines.join("\n")}

        위 피드백을 고려하여 루틴을 생성하세요:
        - 어려웠던 운동은 대체 또는 강도 조절
        - 쉬웠던 운동은 무게/횟수 증가 고려
        - 통증 호소 시 해당 부위 운동 제외 또는 대체
      FEEDBACK
    end

    def format_exercises_catalog
      catalog = []
      Constants::EXERCISES.each do |muscle, data|
        exercises = data[:exercises].map { |e| "#{e[:name]}(#{e[:id]}, 난이도:#{e[:difficulty]}, 장비:#{e[:equipment]})" }
        catalog << "- #{data[:korean]}: #{exercises.join(', ')}"
      end
      catalog.join("\n")
    end

    def format_training_method_details(method)
      case method[:id]
      when "TM01" # fixed_sets_reps
        "- 근력 훈련: BPM에 맞춰 정해진 세트/횟수 정확히 수행"
      when "TM02" # total_reps_fill
        "- 근지구력 훈련(채우기): 총 목표 개수를 채울 때까지 세트 수 무관하게 수행"
      when "TM03" # max_sets_at_fixed_reps
        "- 지속력 훈련: 10개씩 몇 세트까지 지속 가능한지 측정"
      when "TM04" # tabata
        "- 심폐지구력 훈련(타바타): 20초 운동 + 10초 휴식, 8라운드"
      when "TM05" # explosive
        "- 순발력 훈련: 최대 파워로 폭발적 수행, 충분한 휴식 후 다음 세트"
      else
        ""
      end
    end
  end
end
