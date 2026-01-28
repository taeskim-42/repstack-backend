# frozen_string_literal: true

# Service to extract fitness knowledge from YouTube video transcripts
# Uses Claude AI for analysis (Gemini removed)
#
# Usage:
#   1. First extract transcripts: rails youtube:knowledge:extract_transcripts
#   2. Then analyze with Claude: YoutubeKnowledgeExtractionService.analyze_video(video)
#
class YoutubeKnowledgeExtractionService
  KNOWLEDGE_TYPES = FitnessKnowledgeChunk::KNOWLEDGE_TYPES

  SYSTEM_PROMPT = <<~PROMPT
    당신은 전문 피트니스 지식 추출 AI입니다.
    주어진 YouTube 피트니스 영상의 자막을 분석하여 다음 4가지 유형의 지식을 추출합니다:

    1. exercise_technique (운동 기술): 특정 운동의 올바른 수행 방법, 자세, 팁
    2. routine_design (루틴 설계): 운동 프로그램 구성, 분할법, 주간 계획
    3. nutrition_recovery (영양/회복): 식단, 보충제, 휴식, 회복 관련 정보
    4. form_check (자세 체크): 일반적인 실수, 교정 방법, 부상 예방

    각 지식 청크는 독립적으로 의미가 있어야 하며, AI 트레이너가 사용자에게
    조언할 때 참고할 수 있는 형태여야 합니다.
  PROMPT

  # Korean transcript analysis prompt
  ANALYSIS_PROMPT_KO = <<~PROMPT
    아래는 피트니스 YouTube 영상의 자막(트랜스크립트)입니다.
    자막에는 [MM:SS] 형식의 타임스탬프가 포함되어 있습니다.
    이 내용을 분석하여 피트니스 관련 지식을 추출하세요.

    다음 JSON 형식으로 응답하세요:
    {
      "category": "strength|cardio|flexibility|general",
      "difficulty_level": "beginner|intermediate|advanced",
      "language": "ko",
      "summary": "영상 전체 요약",
      "knowledge_chunks": [
        {
          "type": "exercise_technique|routine_design|nutrition_recovery|form_check",
          "content": "상세한 지식 내용 (글자 수 제한 없음, 백과사전처럼 상세하게)",
          "summary": "한 줄 요약",
          "exercise_name": "운동명 (영어, 예: bench_press, squat, deadlift)",
          "muscle_group": "근육 부위 (영어: chest, back, legs, shoulders, arms, core)",
          "difficulty_level": "beginner|intermediate|advanced",
          "timestamp_start": 해당 내용이 시작되는 시간(초),
          "timestamp_end": 해당 내용이 끝나는 시간(초)
        }
      ]
    }

    중요 지침:
    - 자막에서 언급된 모든 유용한 피트니스 정보를 빠짐없이 추출
    - content는 글자 수 제한 없이 최대한 상세하게 작성 (백과사전 수준)
    - 운동 자세, 호흡법, 주의사항, 세트/횟수 권장, 변형 동작 등 모두 포함
    - 지식 청크 개수 제한 없음 - 추출할 수 있는 모든 지식 추출
    - 자막에 피트니스 관련 내용이 없으면 빈 knowledge_chunks 배열 반환
    - 모든 텍스트는 한국어로 작성
    - exercise_name과 muscle_group은 영어로 (검색 및 매칭용)

    ⚠️ 타임스탬프 필수 (REQUIRED):
    - timestamp_start와 timestamp_end는 반드시 입력해야 합니다 (null 불가)
    - 자막의 [MM:SS] 형식을 초 단위 정수로 변환
    - 예: [05:30]이면 timestamp_start: 330
    - 해당 지식이 언급되는 구간의 시작과 끝 시간을 정확히 기록

    자막 내용:
  PROMPT

  # English transcript analysis prompt (translates to Korean + preserves original)
  ANALYSIS_PROMPT_EN = <<~PROMPT
    Below is an English transcript from a fitness YouTube video.
    Timestamps are included in [MM:SS] format.
    Analyze this content and extract fitness knowledge, translating to Korean.

    Respond in the following JSON format:
    {
      "category": "strength|cardio|flexibility|general",
      "difficulty_level": "beginner|intermediate|advanced",
      "language": "en",
      "summary": "영상 전체 요약 (한국어로)",
      "knowledge_chunks": [
        {
          "type": "exercise_technique|routine_design|nutrition_recovery|form_check",
          "content": "한국어로 번역된 상세 지식 내용 (백과사전처럼 상세하게)",
          "content_original": "Original English content (preserve exactly as spoken)",
          "summary": "한 줄 요약 (한국어)",
          "exercise_name": "exercise name in English (e.g., bench_press, squat, deadlift)",
          "muscle_group": "muscle group in English (chest, back, legs, shoulders, arms, core)",
          "difficulty_level": "beginner|intermediate|advanced",
          "timestamp_start": timestamp in seconds,
          "timestamp_end": timestamp in seconds
        }
      ]
    }

    Important instructions:
    - Extract ALL useful fitness information from the transcript
    - "content" must be in Korean (detailed translation)
    - "content_original" must preserve the original English text
    - "summary" must be in Korean
    - exercise_name and muscle_group in English (for search/matching)
    - No limit on content length - be as detailed as possible
    - No limit on number of chunks - extract everything useful
    - Return empty knowledge_chunks array if no fitness content

    ⚠️ TIMESTAMPS REQUIRED:
    - timestamp_start and timestamp_end are mandatory (cannot be null)
    - Convert [MM:SS] format to seconds (e.g., [05:30] = 330)
    - Record exact start and end times for each knowledge chunk

    Transcript:
  PROMPT

  # Alias for backward compatibility
  ANALYSIS_PROMPT = ANALYSIS_PROMPT_KO

  class << self
    # Check if the service is configured (Claude API available)
    def configured?
      AiTrainer::LlmGateway.configured?(task: :knowledge_extraction)
    end

    # Analyze a video that already has transcript extracted
    def analyze_video(video)
      return { error: "Already analyzed" } if video.analyzed?
      return { error: "No transcript available" } if video.transcript.blank?
      raise "Claude API not configured" unless configured?

      language = video.youtube_channel&.language || "ko"
      Rails.logger.info("Analyzing video: #{video.title} (language: #{language})")

      video.start_analysis!

      begin
        result = analyze_transcript(video.transcript, language: language)
        save_knowledge_chunks(video, result, language: language)
        video.complete_analysis!(result)

        Rails.logger.info("Successfully analyzed video: #{video.title}, #{video.fitness_knowledge_chunks.count} chunks")
        result
      rescue StandardError => e
        video.fail_analysis!(e.message)
        Rails.logger.error("Failed to analyze video #{video.id}: #{e.message}")
        raise
      end
    end

    # Analyze videos that have transcripts but haven't been analyzed
    def analyze_pending_videos(limit: 10)
      videos = YoutubeVideo
        .where(analysis_status: "pending")
        .where.not(transcript: [nil, ""])
        .limit(limit)

      results = []

      videos.find_each do |video|
        result = analyze_video(video)
        results << { video_id: video.id, success: true, chunks_count: video.fitness_knowledge_chunks.count }
      rescue StandardError => e
        results << { video_id: video.id, success: false, error: e.message }
      end

      results
    end

    # Analyze transcript text directly
    # @param transcript [String] The transcript text
    # @param language [String] Source language ("ko" or "en")
    def analyze_transcript(transcript, language: "ko")
      raise "Claude API not configured" unless configured?

      analysis_prompt = language == "en" ? ANALYSIS_PROMPT_EN : ANALYSIS_PROMPT_KO
      prompt = "#{analysis_prompt}\n\n#{transcript}"

      response = AiTrainer::LlmGateway.chat(
        prompt: prompt,
        system: SYSTEM_PROMPT,
        task: :knowledge_extraction
      )

      unless response[:success]
        raise "LLM API error: #{response[:error]}"
      end

      parse_response(response[:content])
    end

    # Extract transcript for a video (utility method)
    def extract_transcript(video)
      return video.transcript if video.transcript.present?

      language = video.youtube_channel&.language || "ko"
      transcript = YoutubeChannelScraper.extract_subtitles(video.youtube_url, language: language)
      video.update!(transcript: transcript) if transcript.present?
      transcript
    end

    private

    def parse_response(response)
      # Extract JSON from response (may be wrapped in markdown code block)
      json_str = response.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

      JSON.parse(json_str, symbolize_names: true)
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse response: #{e.message}")
      Rails.logger.error("Response was: #{response}")

      {
        category: "general",
        difficulty_level: "intermediate",
        language: "ko",
        knowledge_chunks: []
      }
    end

    def save_knowledge_chunks(video, result, language: "ko")
      # Clear existing chunks before saving new ones
      video.fitness_knowledge_chunks.destroy_all

      chunks = result[:knowledge_chunks] || []

      chunks.each do |chunk_data|
        next unless valid_chunk?(chunk_data)

        video.fitness_knowledge_chunks.create!(
          knowledge_type: chunk_data[:type],
          content: chunk_data[:content],
          content_original: chunk_data[:content_original], # English original (nil for Korean)
          language: language,
          summary: chunk_data[:summary],
          exercise_name: chunk_data[:exercise_name],
          muscle_group: chunk_data[:muscle_group],
          difficulty_level: chunk_data[:difficulty_level],
          timestamp_start: chunk_data[:timestamp_start],
          timestamp_end: chunk_data[:timestamp_end],
          metadata: {
            source: "claude_extraction",
            extracted_at: Time.current.iso8601
          }
        )
      end
    end

    def valid_chunk?(chunk_data)
      chunk_data[:type].present? &&
        KNOWLEDGE_TYPES.include?(chunk_data[:type]) &&
        chunk_data[:content].present? &&
        chunk_data[:content].length >= 20
    end
  end
end
