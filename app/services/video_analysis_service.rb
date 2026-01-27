# frozen_string_literal: true

# Service for analyzing fitness test videos using Gemini Vision API
# Supports direct YouTube URL analysis and uploaded video files
class VideoAnalysisService
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
    # Analyze a fitness test video using Gemini Vision API
    # @param video_url [String] URL to the video (YouTube URL or presigned URL)
    # @param exercise_type [String] Any exercise type (dynamic)
    # @return [Hash] { success:, rep_count:, form_score:, issues:, feedback: }
    def analyze_video(video_url:, exercise_type: nil)
      unless GeminiConfig.configured?
        Rails.logger.info("[VideoAnalysisService] Gemini API not configured, returning mock response")
        return mock_response(exercise_type)
      end

      prompt = build_prompt(exercise_type)

      # Determine if it's a YouTube URL
      is_youtube = video_url.include?("youtube.com") || video_url.include?("youtu.be")

      response = if is_youtube
                   GeminiConfig.analyze_youtube_video(
                     youtube_url: video_url,
                     prompt: prompt,
                     system_instruction: system_instruction
                   )
                 else
                   # For non-YouTube URLs (like S3/R2 presigned URLs), download and upload to Gemini
                   analyze_from_url(video_url, prompt)
                 end

      parse_analysis_response(response, exercise_type)
    rescue StandardError => e
      Rails.logger.error("[VideoAnalysisService] Error analyzing video: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      { success: false, error: e.message }
    end

    # Analyze uploaded video data directly
    # @param video_data [String] Binary video data (from file upload)
    # @param mime_type [String] MIME type (e.g., "video/mp4", "video/quicktime")
    # @param exercise_type [String] Optional exercise type for specific criteria
    # @return [Hash] { success:, rep_count:, form_score:, issues:, feedback: }
    def analyze_uploaded_video(video_data:, mime_type: "video/mp4", exercise_type: nil)
      unless GeminiConfig.configured?
        Rails.logger.info("[VideoAnalysisService] Gemini API not configured, returning mock response")
        return mock_response(exercise_type)
      end

      prompt = build_prompt(exercise_type)

      Rails.logger.info("[VideoAnalysisService] Analyzing uploaded video (#{video_data.bytesize} bytes, #{mime_type})")

      response = GeminiConfig.analyze_uploaded_video(
        video_data: video_data,
        mime_type: mime_type,
        prompt: prompt,
        system_instruction: system_instruction
      )

      parse_analysis_response(response, exercise_type)
    rescue StandardError => e
      Rails.logger.error("[VideoAnalysisService] Error analyzing uploaded video: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      { success: false, error: e.message }
    end

    # Analyze YouTube video directly by URL
    def analyze_youtube(youtube_url:, exercise_type: nil)
      analyze_video(video_url: youtube_url, exercise_type: exercise_type)
    end

    def api_configured?
      GeminiConfig.configured?
    end

    private

    # Download video from URL and upload to Gemini for analysis
    def analyze_from_url(video_url, prompt)
      Rails.logger.info("[VideoAnalysisService] Downloading video from URL for Gemini upload")

      # Download the video
      video_response = download_video(video_url)
      video_data = video_response[:data]
      mime_type = video_response[:mime_type]

      Rails.logger.info("[VideoAnalysisService] Downloaded #{video_data.bytesize} bytes (#{mime_type})")

      # Upload to Gemini and analyze
      GeminiConfig.analyze_uploaded_video(
        video_data: video_data,
        mime_type: mime_type,
        prompt: prompt,
        system_instruction: system_instruction
      )
    end

    # Download video from presigned URL
    def download_video(url)
      connection = Faraday.new do |conn|
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 120 # 2 minutes for download
        conn.options.open_timeout = 30
      end

      response = connection.get(url)

      unless response.success?
        raise "Failed to download video: HTTP #{response.status}"
      end

      # Determine MIME type from Content-Type header or URL extension
      content_type = response.headers["content-type"]&.split(";")&.first
      mime_type = content_type || mime_type_from_url(url)

      { data: response.body, mime_type: mime_type }
    end

    def mime_type_from_url(url)
      # Extract extension from URL (before query params)
      path = URI.parse(url).path
      ext = File.extname(path).downcase

      case ext
      when ".mp4" then "video/mp4"
      when ".mov" then "video/quicktime"
      when ".avi" then "video/x-msvideo"
      when ".webm" then "video/webm"
      when ".mkv" then "video/x-matroska"
      else "video/mp4" # Default to mp4
      end
    end

    def system_instruction
      <<~INSTRUCTION
        당신은 전문 피트니스 트레이너이자 운동 분석 전문가입니다.
        영상을 보고 운동 횟수를 정확하게 카운트하고, 자세를 평가해주세요.
        반드시 JSON 형식으로만 응답하세요.
      INSTRUCTION
    end

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
        이 영상에서 #{info[:korean_name]}(#{exercise_type}) 운동을 분석해주세요.

        다음 정보를 JSON 형식으로 반환해주세요:
        ```json
        {
          "rep_count": 완료된 정확한 반복 횟수 (숫자),
          "form_score": 자세 점수 (0-100, 정수),
          "issues": ["발견된 자세 문제점 목록"],
          "feedback": "개선을 위한 피드백"
        }
        ```

        자세 평가 기준:
        #{criteria_text}

        중요:
        - 반복 횟수는 완전한 동작(내려갔다 올라오는 것)만 카운트
        - 불완전한 동작은 카운트하지 않음
        - JSON만 반환하고 다른 텍스트는 포함하지 마세요
      PROMPT
    end

    def build_generic_exercise_prompt(exercise_type)
      exercise_name = exercise_type.presence || "운동"

      <<~PROMPT
        이 영상에서 운동을 분석해주세요.

        다음 정보를 JSON 형식으로 반환해주세요:
        ```json
        {
          "exercise_detected": "감지된 운동 종류",
          "rep_count": 완료된 정확한 반복 횟수 (숫자),
          "form_score": 자세 점수 (0-100, 정수),
          "issues": ["발견된 자세 문제점 목록"],
          "feedback": "개선을 위한 피드백"
        }
        ```

        일반적인 자세 평가 기준:
        - 동작 범위(ROM)가 충분한지
        - 자세가 안정적인지
        - 속도와 템포가 적절한지
        - 호흡이 일정한지
        - 부상 위험이 있는 동작이 없는지

        중요:
        - 반복 횟수는 완전한 동작만 카운트
        - 불완전한 동작은 카운트하지 않음
        - JSON만 반환하고 다른 텍스트는 포함하지 마세요
      PROMPT
    end

    def parse_analysis_response(content, exercise_type)
      # Extract JSON from response (in case there's extra text)
      json_match = content.match(/```json\s*([\s\S]*?)\s*```/) || content.match(/\{[\s\S]*\}/)

      if json_match
        json_str = json_match[1] || json_match[0]
        data = JSON.parse(json_str)
      else
        # Try parsing the entire content as JSON
        data = JSON.parse(content)
      end

      {
        success: true,
        exercise_type: data["exercise_detected"] || exercise_type.to_s,
        rep_count: data["rep_count"].to_i,
        form_score: data["form_score"].to_i,
        issues: Array(data["issues"]),
        feedback: data["feedback"].to_s,
        raw_response: data
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[VideoAnalysisService] JSON parse error: #{e.message}")
      Rails.logger.error("Raw content: #{content}")

      # Try to extract numbers from text response
      rep_match = content.match(/(\d+)\s*(?:회|번|개|reps?)/i)
      score_match = content.match(/(\d+)\s*점/i)

      if rep_match
        {
          success: true,
          exercise_type: exercise_type.to_s,
          rep_count: rep_match[1].to_i,
          form_score: score_match ? score_match[1].to_i : 70,
          issues: [],
          feedback: content,
          raw_response: { text: content }
        }
      else
        { success: false, error: "Failed to parse response: #{e.message}", raw_response: content }
      end
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
