# frozen_string_literal: true

# Extracts exercise-specific video clips from structured transcripts.
# Uses Claude to identify exercise segments, then maps caption indices
# back to original timestamps for accuracy.
class ExerciseClipExtractionService
  class ExtractionError < StandardError; end

  MAX_CAPTIONS = 500

  def self.extract(video)
    new(video).extract
  end

  def initialize(video)
    @video = video
    @captions = video.structured_transcript || []
  end

  def extract
    return [] if @captions.empty?

    numbered_captions = build_numbered_captions
    raw_clips = call_claude(numbered_captions)
    build_clips(raw_clips)
  end

  private

  def build_numbered_captions
    @captions.first(MAX_CAPTIONS).map.with_index do |cap, idx|
      start = cap["start"].to_f.round(1)
      text = cap["text"].to_s.strip
      "[#{idx}] #{start}s: \"#{text}\""
    end.join("\n")
  end

  def call_claude(numbered_captions)
    language = @video.youtube_channel&.language || "ko"

    response = AiTrainer::LlmGateway.chat(
      prompt: build_prompt(numbered_captions, language),
      task: :clip_extraction
    )

    return [] unless response[:success]

    parse_response(response[:content])
  end

  def build_prompt(numbered_captions, language)
    <<~PROMPT
      You are a fitness video analyst. Your job is to find segments where the presenter
      is ACTIVELY DEMONSTRATING or TEACHING a specific exercise.

      ## YOUR TASK

      Step 1: Segment this video transcript into topical sections.
      Step 2: For each section, ask: "If a user clicks this timestamp, what exercise
              will they SEE being demonstrated or taught?"
      Step 3: Only extract sections where the answer is a SPECIFIC exercise with
              ACTIONABLE technique instruction.

      Video: "#{@video.title}"
      Channel language: #{language}

      Captions:
      #{numbered_captions}

      ## EXTRACTION RULE: "TIMESTAMP ARRIVAL TEST"

      Imagine a user clicks the YouTube link at the clip's start timestamp.
      The clip is valid ONLY if the user will see/hear:
      - The presenter demonstrating the exercise, OR
      - The presenter explaining specific technique cues (grip, stance, angles, breathing, etc.)

      The clip is INVALID if the user will see/hear:
      - A different exercise being performed while this one is merely mentioned by name
      - A routine listing ("I do bench press, then cable crossover, then...")
      - A passing recommendation ("cable crossover is good for chest")
      - General training philosophy without exercise-specific instruction

      ## MINIMUM QUALITY: 3+ TECHNIQUE CUES

      Each clip MUST contain at least 3 specific, actionable cues. Examples of cues:
      - Grip width/angle, foot placement, body position
      - Movement path, range of motion, tempo
      - Breathing pattern, muscle contraction focus
      - Common mistakes and corrections

      If a segment mentions an exercise but has fewer than 3 cues → DO NOT extract it.

      ## NEGATIVE EXAMPLES (DO NOT EXTRACT)

      ❌ "케이블 크로스오버 하면 좋습니다" → Just a recommendation, not teaching
      ❌ "저는 보통 데드리프트 다음에 바벨로우 합니다" → Routine listing, not instruction
      ❌ "오늘 가슴 운동 했습니다" → Training log, not technique
      ❌ Caption indices 45-47 mention "squat" but indices 40-60 are about deadlift → Wrong exercise tagged

      ## POSITIVE EXAMPLES (EXTRACT THESE)

      ✅ "벤치프레스에서 견갑골을 모으고, 그립 폭은 어깨너비 1.5배로 잡으세요.
          바를 내릴 때 유두 라인을 향해, 팔꿈치 각도는 45도..." → Real technique with multiple cues
      ✅ "랫풀다운 할 때 가장 중요한 건 팔꿈치를 옆구리로 당긴다는 느낌.
          상체를 살짝 뒤로 기울이고, 바를 쇄골 쪽으로..." → Specific form instruction

      ## OUTPUT FORMAT

      For each valid clip:
      - exercise_name: English snake_case (e.g., "bench_press", "lat_pulldown"). Use SPECIFIC names, never "back_exercise" or "general_training".
      - muscle_group: "chest", "back", "legs", "shoulders", "arms", "core"
      - clip_type: "technique", "form_check", "pro_tip", "common_mistake"
      - title: Short title in #{language == "ko" ? "Korean" : "English"}
      - content: 3-5 sentences of actionable knowledge in #{language == "ko" ? "Korean" : "English"}
      - summary: One-line summary in #{language == "ko" ? "Korean" : "English"}
      - caption_start_index: [index] where this exercise teaching BEGINS
      - caption_end_index: [index] where this exercise teaching ENDS
      - difficulty_level: "beginner", "intermediate", "advanced"

      IMPORTANT:
      - Indices MUST be valid numbers from the captions above
      - The exercise at caption_start_index must MATCH exercise_name (timestamp arrival test)
      - QUALITY OVER QUANTITY: 0-3 precise clips >>> 10 noisy clips
      - No exercise teaching found? Return: {"exercise_clips": []}

      Return ONLY valid JSON:
      {"exercise_clips": [...]}
    PROMPT
  end

  def parse_response(text)
    return [] if text.blank?

    json_str = text[/\{.*\}/m]
    return [] if json_str.blank?

    data = JSON.parse(json_str)
    data["exercise_clips"] || []
  rescue JSON::ParserError => e
    Rails.logger.error("[ExerciseClipExtraction] JSON parse failed: #{e.message}")
    []
  end

  def build_clips(raw_clips)
    raw_clips.filter_map do |clip|
      build_single_clip(clip)
    end
  end

  def build_single_clip(clip)
    start_idx = clip["caption_start_index"].to_i
    end_idx = clip["caption_end_index"].to_i

    return nil if start_idx < 0 || end_idx < 0
    return nil if start_idx >= @captions.length || end_idx >= @captions.length
    return nil if start_idx > end_idx

    start_cap = @captions[start_idx]
    end_cap = @captions[end_idx]

    timestamp_start = start_cap["start"].to_f
    timestamp_end = end_cap["start"].to_f + (end_cap["duration"]&.to_f || 3.0)

    language = @video.youtube_channel&.language || "ko"

    ExerciseVideoClip.create!(
      youtube_video: @video,
      exercise_name: clip["exercise_name"].to_s.strip,
      muscle_group: clip["muscle_group"],
      clip_type: clip["clip_type"] || "technique",
      title: clip["title"].to_s.strip,
      content: clip["content"].to_s.strip,
      content_original: language == "en" ? clip["content"].to_s.strip : nil,
      summary: clip["summary"],
      timestamp_start: timestamp_start,
      timestamp_end: timestamp_end,
      caption_indices: (start_idx..end_idx).to_a,
      source_language: language,
      difficulty_level: clip["difficulty_level"],
      metadata: { extracted_at: Time.current.iso8601 }
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[ExerciseClipExtraction] Failed to create clip: #{e.message}")
    nil
  end
end
