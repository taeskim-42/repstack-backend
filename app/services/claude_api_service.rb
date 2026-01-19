# frozen_string_literal: true

class ClaudeApiService
  # Custom error classes for precise error handling
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error
    attr_reader :status_code, :response_body

    def initialize(message, status_code: nil, response_body: nil)
      @status_code = status_code
      @response_body = response_body
      super(message)
    end
  end
  class TimeoutError < Error; end
  class ParseError < Error; end
  class ValidationError < Error; end
  class RateLimitError < ApiError; end
  class CircuitOpenError < Error; end

  API_URL = "https://api.anthropic.com/v1/messages"
  MODEL = "claude-sonnet-4-20250514"
  MAX_TOKENS = 4096

  # Timeout configuration (in seconds)
  CONNECT_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 30

  # Retry configuration
  MAX_RETRIES = 2
  RETRY_DELAY = 1

  # Circuit breaker configuration
  CIRCUIT_BREAKER_NAME = :claude_api
  CIRCUIT_VOLUME_THRESHOLD = 5      # Minimum requests before circuit can open
  CIRCUIT_ERROR_THRESHOLD = 50      # Error percentage to open circuit
  CIRCUIT_SLEEP_WINDOW = 60         # Seconds to wait before trying again (must be >= time_window)
  CIRCUIT_TIME_WINDOW = 60          # Time window for error rate calculation

  # Valid input values for sanitization
  VALID_LEVELS = %w[beginner intermediate advanced 초급 중급 고급].freeze
  MAX_WEEK = 52
  MAX_DAY = 7

  # Required fields in AI response
  REQUIRED_ROUTINE_FIELDS = %w[workoutType exercises].freeze
  REQUIRED_EXERCISE_FIELDS = %w[exerciseName targetMuscle sets reps].freeze

  def initialize
    @api_key = ENV["ANTHROPIC_API_KEY"]
    @conn = build_connection
  end

  # Class method to access circuit breaker status
  def self.circuit_breaker
    Circuitbox.circuit(
      CIRCUIT_BREAKER_NAME,
      exceptions: [TimeoutError, ApiError, RateLimitError, Faraday::Error],
      volume_threshold: CIRCUIT_VOLUME_THRESHOLD,
      error_threshold: CIRCUIT_ERROR_THRESHOLD,
      sleep_window: CIRCUIT_SLEEP_WINDOW,
      time_window: CIRCUIT_TIME_WINDOW
    )
  end

  def self.circuit_open?
    circuit_breaker.open?
  end

  def self.circuit_stats
    cb = circuit_breaker
    {
      open: cb.open?,
      error_rate: cb.error_rate,
      success_count: cb.success_count,
      failure_count: cb.failure_count
    }
  end

  # Returns a Result object with success/failure information
  # Never silently falls back to mock data
  # Uses circuit breaker pattern to prevent cascading failures
  def generate_routine(level:, week:, day:, body_info: {}, recent_workouts: [])
    # Validate and sanitize inputs first (before circuit breaker)
    sanitized_params = sanitize_and_validate_inputs(level: level, week: week, day: day)

    if @api_key.blank?
      Rails.logger.warn("ClaudeApiService: API key not configured, using mock data")
      return build_result(success: true, data: mock_routine, mock: true)
    end

    # Use circuit breaker for external API calls
    self.class.circuit_breaker.run do
      prompt = build_routine_prompt(
        sanitized_params[:level],
        sanitized_params[:week],
        sanitized_params[:day],
        body_info,
        recent_workouts
      )

      response = call_api_with_retry(prompt)
      parsed_response = parse_and_validate_response(response)

      build_result(success: true, data: parsed_response)
    end
  rescue Circuitbox::OpenCircuitError
    Rails.logger.warn("ClaudeApiService: Circuit breaker is open, using mock data")
    build_result(
      success: true,
      data: mock_routine,
      mock: true,
      error: "AI 서비스가 일시적으로 불안정합니다. 기본 루틴을 제공합니다.",
      error_type: :circuit_open
    )
  rescue ConfigurationError => e
    Rails.logger.error("ClaudeApiService Configuration Error: #{e.message}")
    build_result(success: false, error: e.message, error_type: :configuration)
  rescue ValidationError => e
    Rails.logger.error("ClaudeApiService Validation Error: #{e.message}")
    build_result(success: false, error: e.message, error_type: :validation)
  rescue RateLimitError => e
    Rails.logger.error("ClaudeApiService Rate Limited: #{e.message}")
    build_result(success: false, error: "서비스가 일시적으로 바쁩니다. 잠시 후 다시 시도해주세요.", error_type: :rate_limit)
  rescue TimeoutError => e
    Rails.logger.error("ClaudeApiService Timeout: #{e.message}")
    build_result(success: false, error: "AI 서비스 응답 시간이 초과되었습니다.", error_type: :timeout)
  rescue ApiError => e
    Rails.logger.error("ClaudeApiService API Error: #{e.message} (status: #{e.status_code})")
    build_result(success: false, error: "AI 서비스 오류가 발생했습니다.", error_type: :api)
  rescue ParseError => e
    Rails.logger.error("ClaudeApiService Parse Error: #{e.message}")
    build_result(success: false, error: "AI 응답을 처리할 수 없습니다.", error_type: :parse)
  rescue StandardError => e
    Rails.logger.error("ClaudeApiService Unexpected Error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    build_result(success: false, error: "예상치 못한 오류가 발생했습니다.", error_type: :unknown)
  end

  private

  def build_connection
    Faraday.new(url: API_URL) do |f|
      f.request :json
      f.response :json
      f.options.timeout = READ_TIMEOUT
      f.options.open_timeout = CONNECT_TIMEOUT
      f.options.write_timeout = WRITE_TIMEOUT
      f.adapter Faraday.default_adapter
    end
  end

  def build_result(success:, data: nil, error: nil, error_type: nil, mock: false)
    {
      success: success,
      data: data,
      error: error,
      error_type: error_type,
      mock: mock
    }
  end

  def sanitize_and_validate_inputs(level:, week:, day:)
    # Sanitize level - only allow known values
    sanitized_level = level.to_s.downcase.strip
    unless VALID_LEVELS.include?(sanitized_level)
      raise ValidationError, "Invalid level: #{level}. Must be one of: #{VALID_LEVELS.join(', ')}"
    end

    # Sanitize week - must be positive integer within range
    sanitized_week = week.to_i
    unless sanitized_week.between?(1, MAX_WEEK)
      raise ValidationError, "Invalid week: #{week}. Must be between 1 and #{MAX_WEEK}"
    end

    # Sanitize day - must be positive integer within range
    sanitized_day = day.to_i
    unless sanitized_day.between?(1, MAX_DAY)
      raise ValidationError, "Invalid day: #{day}. Must be between 1 and #{MAX_DAY}"
    end

    { level: sanitized_level, week: sanitized_week, day: sanitized_day }
  end

  def call_api_with_retry(prompt)
    retries = 0

    begin
      call_api(prompt)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      retries += 1
      if retries <= MAX_RETRIES
        Rails.logger.warn("ClaudeApiService: Retry #{retries}/#{MAX_RETRIES} after #{e.class}")
        sleep(RETRY_DELAY * retries)
        retry
      end
      raise TimeoutError, "Connection failed after #{MAX_RETRIES} retries: #{e.message}"
    end
  end

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

    handle_api_response(response)
  rescue Faraday::TimeoutError => e
    raise TimeoutError, "Request timed out: #{e.message}"
  end

  def handle_api_response(response)
    case response.status
    when 200
      body = response.body
      content = body.dig("content", 0, "text")
      raise ApiError.new("Empty response from API", status_code: 200, response_body: body) if content.blank?
      content
    when 429
      raise RateLimitError.new("Rate limit exceeded", status_code: 429, response_body: response.body)
    when 401, 403
      raise ConfigurationError, "Authentication failed. Please check API key."
    when 400
      raise ApiError.new("Bad request: #{response.body}", status_code: 400, response_body: response.body)
    when 500..599
      raise ApiError.new("Server error", status_code: response.status, response_body: response.body)
    else
      raise ApiError.new("Unexpected status", status_code: response.status, response_body: response.body)
    end
  end

  def parse_and_validate_response(response)
    parsed = parse_routine_response(response)
    validate_routine_structure(parsed)
    parsed
  end

  def validate_routine_structure(routine)
    # Validate required top-level fields (excluding exercises which is checked separately)
    missing_fields = (REQUIRED_ROUTINE_FIELDS - ["exercises"]).reject { |f| routine.key?(f) && routine[f].present? }
    unless missing_fields.empty?
      raise ValidationError, "Missing required fields in routine: #{missing_fields.join(', ')}"
    end

    # Validate exercises array separately (empty array should give specific message)
    exercises = routine["exercises"]
    unless exercises.is_a?(Array)
      raise ValidationError, "Missing required fields in routine: exercises"
    end
    unless exercises.any?
      raise ValidationError, "Routine must contain at least one exercise"
    end

    # Validate each exercise has required fields
    exercises.each_with_index do |exercise, index|
      missing_exercise_fields = REQUIRED_EXERCISE_FIELDS.reject { |f| exercise.key?(f) }
      unless missing_exercise_fields.empty?
        raise ValidationError, "Exercise #{index + 1} missing required fields: #{missing_exercise_fields.join(', ')}"
      end

      # Validate numeric fields
      unless exercise["sets"].is_a?(Integer) && exercise["sets"].positive?
        raise ValidationError, "Exercise #{index + 1}: sets must be a positive integer"
      end

      unless exercise["reps"].is_a?(Integer) && exercise["reps"].positive?
        raise ValidationError, "Exercise #{index + 1}: reps must be a positive integer"
      end
    end

    true
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
                  "setDurationSeconds": 45,
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
    
    # Handle additional fields
    if body_info[:max_lifts].present?
      parts << "최대 중량 기록: #{body_info[:max_lifts]}"
    end
    
    if body_info[:recent_workouts].present?
      parts << "최근 운동 기록: #{body_info[:recent_workouts].length}개 기록"
    end
    
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
    raise ParseError, "Empty response received" if response.blank?

    # Try to extract JSON from markdown code blocks first
    json_str = extract_json_from_response(response)

    begin
      parsed = JSON.parse(json_str)

      # Ensure we got a hash back
      unless parsed.is_a?(Hash)
        raise ParseError, "Expected JSON object, got #{parsed.class}"
      end

      parsed
    rescue JSON::ParserError => e
      # Log the problematic response for debugging (truncated)
      truncated_response = response.length > 500 ? "#{response[0..500]}..." : response
      Rails.logger.error("JSON parse error: #{e.message}")
      Rails.logger.error("Response content: #{truncated_response}")
      raise ParseError, "Failed to parse AI response as JSON: #{e.message}"
    end
  end

  def extract_json_from_response(response)
    # Try markdown code block first
    json_match = response.match(/```json\s*(.*?)\s*```/m)
    return json_match[1].strip if json_match

    # Try to find JSON object boundaries
    if response.include?("{")
      start_idx = response.index("{")
      end_idx = response.rindex("}")

      if start_idx && end_idx && end_idx > start_idx
        # Validate that braces are balanced before returning
        potential_json = response[start_idx..end_idx]
        return potential_json if balanced_braces?(potential_json)
      end
    end

    # Return as-is and let JSON.parse handle errors
    response
  end

  def balanced_braces?(str)
    count = 0
    str.each_char do |c|
      case c
      when "{" then count += 1
      when "}" then count -= 1
      end
      return false if count.negative?
    end
    count.zero?
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
          "setDurationSeconds" => 20,
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
          "setDurationSeconds" => 20,
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
          "setDurationSeconds" => 30,
          "restDurationSeconds" => 30,
          "rangeOfMotion" => "full",
          "howTo" => "팔꿈치를 바닥에 대고 몸을 일직선으로 유지합니다.",
          "purpose" => "코어 안정성 강화"
        }
      ]
    }
  end
end