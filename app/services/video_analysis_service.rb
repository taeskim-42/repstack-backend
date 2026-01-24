# frozen_string_literal: true

# Service for analyzing fitness test videos using Claude Vision API
class VideoAnalysisService
  # Claude Vision model for video analysis
  MODEL = "claude-sonnet-4-20250514"
  MAX_TOKENS = 2048
  API_URL = "https://api.anthropic.com/v1/messages"
  API_VERSION = "2023-06-01"

  # Known exercise types with specific evaluation criteria
  EXERCISE_CRITERIA = {
    # Bodyweight exercises
    "pushup" => {
      korean_name: "푸쉬업",
      criteria: [
        "몸이 일직선을 유지하는지",
        "팔꿈치 각도가 적절한지 (90도 이상 내려가는지)",
        "코어가 안정적인지 (허리가 처지지 않는지)",
        "호흡이 일정한지",
        "속도가 적절한지"
      ]
    },
    "squat" => {
      korean_name: "스쿼트",
      criteria: [
        "무릎이 발끝을 넘어가지 않는지",
        "허벅지가 바닥과 평행해지는지 (깊이)",
        "허리가 곧게 유지되는지",
        "무릎이 안쪽으로 모이지 않는지",
        "발뒤꿈치가 떨어지지 않는지"
      ]
    },
    "pullup" => {
      korean_name: "턱걸이",
      criteria: [
        "팔이 완전히 펴지는지 (데드행)",
        "턱이 바를 넘어가는지",
        "몸의 흔들림이 적은지",
        "어깨가 내려가고 견갑골을 모으는지",
        "당기는 동작이 부드러운지"
      ]
    },
    # Barbell exercises
    "bench_press" => {
      korean_name: "벤치프레스",
      criteria: [
        "바가 가슴 중앙에 내려오는지",
        "팔꿈치 각도가 45-75도인지",
        "어깨가 벤치에 고정되어 있는지",
        "등 아치가 적절한지",
        "손목이 중립을 유지하는지"
      ]
    },
    "deadlift" => {
      korean_name: "데드리프트",
      criteria: [
        "허리가 중립을 유지하는지",
        "바가 몸에 가깝게 움직이는지",
        "힙힌지가 적절한지",
        "무릎이 발끝과 같은 방향인지",
        "록아웃 시 과도한 젖힘이 없는지"
      ]
    },
    "barbell_squat" => {
      korean_name: "바벨 스쿼트",
      criteria: [
        "바 위치가 적절한지 (하이바/로우바)",
        "깊이가 충분한지 (대퇴부 평행 이상)",
        "무릎이 발끝 방향으로 움직이는지",
        "상체 기울기가 적절한지",
        "코어가 단단하게 유지되는지"
      ]
    }
  }.freeze

  class << self
    # Analyze a fitness test video using Claude Vision API
    # @param video_url [String] Presigned URL to the video
    # @param exercise_type [String] Any exercise type (dynamic)
    # @return [Hash] { success:, rep_count:, form_score:, issues:, feedback: }
    def analyze_video(video_url:, exercise_type:)
      unless api_configured?
        Rails.logger.info("[VideoAnalysisService] API not configured, returning mock response")
        return mock_response(exercise_type)
      end

      prompt = build_prompt(exercise_type)
      response = call_claude_vision(video_url: video_url, prompt: prompt)

      if response[:success]
        parse_analysis_response(response[:content], exercise_type)
      else
        response
      end
    rescue StandardError => e
      Rails.logger.error("[VideoAnalysisService] Error analyzing video: #{e.message}")
      { success: false, error: e.message }
    end

    def api_configured?
      ENV["ANTHROPIC_API_KEY"].present?
    end

    private

    def build_prompt(exercise_type)
      exercise_info = EXERCISE_CRITERIA[exercise_type]

      if exercise_info
        build_known_exercise_prompt(exercise_type, exercise_info)
      else
        build_generic_exercise_prompt(exercise_type)
      end
    end

    def build_known_exercise_prompt(exercise_type, info)
      criteria_text = info[:criteria].map.with_index { |c, i| "#{i + 1}. #{c}" }.join("\n")

      <<~PROMPT
        당신은 전문 피트니스 트레이너입니다. 이 영상에서 #{info[:korean_name]}(#{exercise_type}) 운동을 분석해주세요.

        다음 정보를 JSON 형식으로 반환해주세요:
        1. rep_count: 완료된 정확한 반복 횟수 (숫자)
        2. form_score: 자세 점수 (0-100, 정수)
        3. issues: 발견된 자세 문제점 목록 (배열)
        4. feedback: 개선을 위한 피드백 (문자열)

        자세 평가 기준:
        #{criteria_text}

        JSON만 반환하고 다른 텍스트는 포함하지 마세요.
      PROMPT
    end

    def build_generic_exercise_prompt(exercise_type)
      <<~PROMPT
        당신은 전문 피트니스 트레이너입니다. 이 영상에서 #{exercise_type} 운동을 분석해주세요.

        다음 정보를 JSON 형식으로 반환해주세요:
        1. rep_count: 완료된 정확한 반복 횟수 (숫자)
        2. form_score: 자세 점수 (0-100, 정수)
        3. issues: 발견된 자세 문제점 목록 (배열)
        4. feedback: 개선을 위한 피드백 (문자열)

        일반적인 자세 평가 기준:
        - 동작 범위(ROM)가 충분한지
        - 자세가 안정적인지
        - 속도와 템포가 적절한지
        - 호흡이 일정한지
        - 부상 위험이 있는 동작이 없는지

        JSON만 반환하고 다른 텍스트는 포함하지 마세요.
      PROMPT
    end

    def call_claude_vision(video_url:, prompt:)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120 # Video analysis can take longer

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
      request["anthropic-version"] = API_VERSION

      body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "video",
                source: {
                  type: "url",
                  url: video_url
                }
              },
              {
                type: "text",
                text: prompt
              }
            ]
          }
        ]
      }

      request.body = body.to_json

      response = http.request(request)

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        {
          success: true,
          content: data.dig("content", 0, "text"),
          usage: {
            input_tokens: data.dig("usage", "input_tokens"),
            output_tokens: data.dig("usage", "output_tokens")
          }
        }
      else
        Rails.logger.error("[VideoAnalysisService] API error: #{response.code} - #{response.body}")
        { success: false, error: "API returned #{response.code}" }
      end
    end

    def parse_analysis_response(content, exercise_type)
      # Extract JSON from response (in case there's extra text)
      json_match = content.match(/\{[\s\S]*\}/)
      return { success: false, error: "No JSON found in response" } unless json_match

      data = JSON.parse(json_match[0])

      {
        success: true,
        exercise_type: exercise_type.to_s,
        rep_count: data["rep_count"].to_i,
        form_score: data["form_score"].to_i,
        issues: Array(data["issues"]),
        feedback: data["feedback"].to_s,
        raw_response: data
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[VideoAnalysisService] JSON parse error: #{e.message}")
      { success: false, error: "Failed to parse response: #{e.message}" }
    end

    # Mock response for testing without API key
    def mock_response(exercise_type)
      mock_data = {
        "pushup" => { rep_count: 15, form_score: 75 },
        "squat" => { rep_count: 20, form_score: 80 },
        "pullup" => { rep_count: 8, form_score: 70 },
        "bench_press" => { rep_count: 10, form_score: 75 },
        "deadlift" => { rep_count: 8, form_score: 70 },
        "barbell_squat" => { rep_count: 12, form_score: 75 }
      }

      data = mock_data[exercise_type] || { rep_count: 10, form_score: 70 }

      {
        success: true,
        exercise_type: exercise_type.to_s,
        rep_count: data[:rep_count],
        form_score: data[:form_score],
        issues: ["이것은 테스트 응답입니다."],
        feedback: "API가 설정되면 실제 영상 분석 결과를 받을 수 있습니다.",
        raw_response: { mock: true }
      }
    end
  end
end
