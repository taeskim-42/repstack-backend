# frozen_string_literal: true

class ClaudeApiService
  API_URL = "https://api.anthropic.com/v1/messages"
  MODEL = "claude-sonnet-4-20250514"
  MAX_TOKENS = 4096

  def initialize
    @api_key = ENV["ANTHROPIC_API_KEY"]
    @conn = Faraday.new(url: API_URL) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def generate_routine(level:, week:, day:, body_info: {}, recent_workouts: [])
    return mock_routine if @api_key.blank?

    prompt = build_routine_prompt(level, week, day, body_info, recent_workouts)
    response = call_api(prompt)
    parse_routine_response(response)
  rescue StandardError => e
    Rails.logger.error("Claude API Error: #{e.message}")
    mock_routine
  end

  private

  def call_api(prompt)
    response = @conn.post do |req|
      req.headers["x-api-key"] = @api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.headers["Content-Type"] = "application/json"
      req.body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [{ role: "user", content: prompt }]
      }
    end

    if response.success?
      body = response.body
      content = body.dig("content", 0, "text")
      content || ""
    else
      Rails.logger.error("Claude API failed: #{response.status} - #{response.body}")
      ""
    end
  end

  def build_routine_prompt(level, week, day, body_info, recent_workouts)
    template = get_workout_template(level, week, day)

    <<~PROMPT
      당신은 전문 피트니스 트레이너입니다. 아래의 운동 프로그램 템플릿을 기반으로 사용자 맞춤 루틴을 생성해주세요.

      ## 사용자 정보
      현재 레벨: #{level}
      주차: #{week}주차
      일차: Day #{day}

      ## 신체 정보
      #{format_body_info(body_info)}

      ## 최근 운동 기록
      #{format_recent_workouts(recent_workouts)}

      #{template}

      ## 출력 형식
      반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트를 추가하지 마세요.

      ```json
      {
          "workoutType": "strength|muscularEndurance|sustainability|cardio|strengthExplosive",
          "dayOfWeek": "MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY",
          "estimatedDuration": 45,
          "exercises": [
              {
                  "exerciseName": "운동명",
                  "targetMuscle": "chest|back|legs|core|shoulders|arms|fullBody",
                  "sets": 3,
                  "reps": 10,
                  "weight": null,
                  "weightDescription": "10회 가능한 무게",
                  "bpm": 30,
                  "restDurationSeconds": 60,
                  "rangeOfMotion": "short|medium|full",
                  "howTo": "운동 수행 방법",
                  "purpose": "운동 목적"
              }
          ]
      }
      ```
    PROMPT
  end

  def format_body_info(body_info)
    return "신체 정보 미입력" if body_info.blank?

    parts = []
    parts << "키: #{body_info[:height]}cm" if body_info[:height]
    parts << "체중: #{body_info[:weight]}kg" if body_info[:weight]
    parts << "체지방률: #{body_info[:body_fat]}%" if body_info[:body_fat]
    parts.join("\n")
  end

  def format_recent_workouts(recent_workouts)
    return "최근 운동 기록 없음" if recent_workouts.blank?

    recent_workouts.map do |w|
      "#{w[:name]}: #{w[:weight]}kg x #{w[:reps]}회"
    end.join("\n")
  end

  def get_workout_template(level, week, day)
    case level.to_s.downcase
    when "beginner", "초급"
      beginner_template(week, day)
    when "intermediate", "중급"
      intermediate_template(week, day)
    when "advanced", "고급"
      advanced_template(week, day)
    else
      beginner_template(week, day)
    end
  end

  def beginner_template(week, day)
    day_of_week = %w[MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY][day.to_i - 1] || "MONDAY"
    workout_types = %w[근력 근지구력 지속력 근력 심폐지구력]
    workout_type = workout_types[day.to_i - 1] || "근력"

    <<~TEMPLATE
      ## 초급 프로그램 템플릿 (#{week}주차 Day#{day} - #{day_of_week})

      ### 운동 유형: #{workout_type}

      ### 프로그램 규칙
      - 주 5일 운동 (월~금)
      - Day1(월), Day4(목): 근력 - BPM 30으로 정해진 세트/횟수 수행
      - Day2(화): 근지구력 - 총 목표 개수 채우기 (각 세트 최대 횟수)
      - Day3(수): 지속력 - BPM 30으로 10개씩 몇 세트 지속 가능한지 확인
      - Day5(금): 심폐지구력 - 타바타 (20초 운동 + 10초 휴식)

      ### 타겟 근육 (매일 4개 부위)
      1. 가슴: 푸시업, BPM 푸시업, 벤치프레스
      2. 등: 턱걸이(9칸), 렛풀다운, 데드리프트
      3. 하체: 기둥 스쿼트, 스쿼트
      4. 복근: 복근 운동

      ### #{week}주차 기준값
      - BPM: 30 (초급 기본)
      - 가동범위: 풀(full) 기본, 심폐지구력은 깔(short)

      ### 운동별 무게 설정
      - 푸시업: "10회 가능한 칸" (난이도 조절)
      - 턱걸이: 9칸 어시스트 또는 "10회 가능한 무게"
      - 스쿼트: 1주차 맨몸 → 3주차 30kg → 4주차 키-100kg
    TEMPLATE
  end

  def intermediate_template(week, day)
    <<~TEMPLATE
      ## 중급 프로그램 템플릿 (#{week}주차 Day#{day})

      ### 중급 특징
      - 대부분의 운동인들이 머무르는 구역
      - 세 단계: 정상인 → 건강인 → 운동인

      ### 프로그램 구성
      - 초급보다 높은 볼륨과 강도
      - 복합 운동 위주
      - 분할 훈련 도입 가능
      - BPM 점진적 증가 (30 → 40 → 50)

      ### 타겟 근육
      1. 가슴: 벤치프레스, 인클라인 프레스, 딥스
      2. 등: 데드리프트, 바벨로우, 풀업
      3. 하체: 스쿼트, 런지, 레그프레스
      4. 어깨: 오버헤드프레스, 레터럴레이즈
      5. 복근: 행잉레그레이즈, 플랭크
    TEMPLATE
  end

  def advanced_template(week, day)
    <<~TEMPLATE
      ## 고급 프로그램 템플릿 (#{week}주차 Day#{day})

      ### 고급 특징
      - 운동의 자유가 주어짐
      - 스스로 변인들을 조합
      - 주당 운동 강도(Volume) 직접 구성

      ### 고급 변인 조합
      - BPM: 20~120 자유 설정
      - 가동범위: 목적에 따라 조절
      - 템포: 이센트릭/컨센트릭 조절
      - 휴식 시간: 목표에 따라 30초~3분

      ### 추천 분할
      - PPL (Push/Pull/Legs)
      - 상체/하체 분할
      - 근육별 분할 (5분할)
    TEMPLATE
  end

  def parse_routine_response(response)
    return mock_routine if response.blank?

    json_match = response.match(/```json\s*(.*?)\s*```/m)
    json_str = json_match ? json_match[1] : response

    if json_str.include?("{")
      start_idx = json_str.index("{")
      end_idx = json_str.rindex("}")
      json_str = json_str[start_idx..end_idx] if start_idx && end_idx
    end

    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error("JSON parse error: #{e.message}")
    mock_routine
  end

  def mock_routine
    {
      "workoutType" => "strength",
      "dayOfWeek" => "MONDAY",
      "estimatedDuration" => 45,
      "exercises" => [
        {
          "exerciseName" => "푸시업",
          "targetMuscle" => "chest",
          "sets" => 3,
          "reps" => 10,
          "weight" => nil,
          "weightDescription" => "체중",
          "bpm" => 30,
          "restDurationSeconds" => 60,
          "rangeOfMotion" => "full",
          "howTo" => "가슴이 바닥에 닿을 때까지 내려간 후 팔을 완전히 펴서 올라옵니다.",
          "purpose" => "가슴 근력 강화"
        },
        {
          "exerciseName" => "스쿼트",
          "targetMuscle" => "legs",
          "sets" => 3,
          "reps" => 10,
          "weight" => nil,
          "weightDescription" => "맨몸",
          "bpm" => 30,
          "restDurationSeconds" => 60,
          "rangeOfMotion" => "full",
          "howTo" => "허벅지가 바닥과 평행이 될 때까지 앉았다 일어납니다.",
          "purpose" => "하체 근력 강화"
        },
        {
          "exerciseName" => "플랭크",
          "targetMuscle" => "core",
          "sets" => 3,
          "reps" => 1,
          "weight" => nil,
          "weightDescription" => "30초 유지",
          "bpm" => nil,
          "restDurationSeconds" => 30,
          "rangeOfMotion" => "full",
          "howTo" => "팔꿈치를 바닥에 대고 몸을 일직선으로 유지합니다.",
          "purpose" => "코어 안정성 강화"
        }
      ]
    }
  end
end
