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
      You are a fitness knowledge extraction expert.

      Analyze this YouTube video transcript and extract exercise-specific knowledge clips.
      Each clip should cover ONE specific topic about ONE exercise.

      Video: "#{@video.title}"
      Channel language: #{language}

      Captions:
      #{numbered_captions}

      For each exercise knowledge clip found, return:
      - exercise_name: English snake_case (e.g., "bench_press", "squat", "lat_pulldown")
      - muscle_group: One of "chest", "back", "legs", "shoulders", "arms", "core", "cardio"
      - clip_type: One of "technique", "form_check", "pro_tip", "common_mistake"
      - title: Short descriptive title in #{language == "ko" ? "Korean" : "English"}
      - content: Detailed knowledge in #{language == "ko" ? "Korean" : "English"} (2-4 sentences)
      - summary: One-line summary in #{language == "ko" ? "Korean" : "English"}
      - caption_start_index: The [index] where this clip starts
      - caption_end_index: The [index] where this clip ends
      - difficulty_level: "beginner", "intermediate", or "advanced"

      IMPORTANT:
      - caption_start_index and caption_end_index MUST be valid indices from the captions above
      - Each clip should reference a continuous segment of captions
      - Extract ALL distinct exercise knowledge segments (typically 3-10 per video)
      - If the video doesn't contain exercise knowledge, return an empty array

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
