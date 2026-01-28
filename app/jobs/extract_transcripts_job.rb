# frozen_string_literal: true

# Background job to extract transcripts and trigger full pipeline
# Pipeline: transcript → Claude analysis → embeddings
#
# Usage:
#   ExtractTranscriptsJob.perform_async          # Process all (up to 100)
#   ExtractTranscriptsJob.perform_async(50)      # Process 50 videos
#   ExtractTranscriptsJob.perform_async(50, true) # Pipeline mode (analyze + embed)
#
class ExtractTranscriptsJob
  include Sidekiq::Job

  sidekiq_options queue: :low, retry: 1

  # Process videos without transcripts
  # @param limit [Integer] Maximum number of videos to process (default: 100)
  # @param pipeline [Boolean] If true, trigger analysis + embedding after transcript (default: true)
  # @param language [String] Filter by channel language: "en", "ko", or nil for all
  def perform(limit = 100, pipeline = true, language = nil)
    scope = YoutubeVideo.where(transcript: [nil, ""])

    # Filter by channel language if specified
    if language.present?
      scope = scope.joins(:youtube_channel).where(youtube_channels: { language: language })
    end

    videos = scope.limit(limit).order(:id)

    total = videos.count
    Rails.logger.info("[ExtractTranscripts] Starting: #{total} videos (pipeline=#{pipeline})")

    success = 0
    failed = 0
    no_subs = 0

    videos.find_each.with_index do |video, index|
      result = extract_single(video, index + 1, total, pipeline)

      case result
      when :success then success += 1
      when :no_subs then no_subs += 1
      when :failed then failed += 1
      end

      # Rate limiting: 3 seconds between requests to avoid YouTube blocks
      sleep 3
    end

    Rails.logger.info(
      "[ExtractTranscripts] Complete: success=#{success}, no_subs=#{no_subs}, failed=#{failed}"
    )

    # Auto-continue: if there are more videos, queue the next batch
    remaining_scope = YoutubeVideo.where(transcript: [nil, ""])
    remaining_scope = remaining_scope.joins(:youtube_channel).where(youtube_channels: { language: language }) if language.present?
    remaining = remaining_scope.count

    if remaining > 0
      Rails.logger.info("[ExtractTranscripts] #{remaining} videos remaining for #{language || 'all'}, queuing next batch...")
      ExtractTranscriptsJob.perform_in(10.seconds, limit, pipeline, language)
    elsif language == "en"
      # English done, start Korean automatically
      ko_remaining = YoutubeVideo.where(transcript: [nil, ""])
                                 .joins(:youtube_channel)
                                 .where(youtube_channels: { language: "ko" })
                                 .count
      if ko_remaining > 0
        Rails.logger.info("[ExtractTranscripts] English complete! Starting Korean (#{ko_remaining} videos)...")
        ExtractTranscriptsJob.perform_in(10.seconds, limit, pipeline, "ko")
      else
        Rails.logger.info("[ExtractTranscripts] All languages complete!")
      end
    else
      Rails.logger.info("[ExtractTranscripts] All videos processed for language=#{language || 'all'}!")
    end

    { success: success, no_subs: no_subs, failed: failed, remaining: remaining }
  end

  private

  def extract_single(video, current, total, pipeline)
    language = video.youtube_channel&.language || "ko"
    Rails.logger.info("[ExtractTranscripts] [#{current}/#{total}] Processing: #{video.title.truncate(50)} (#{language})")

    transcript = YoutubeChannelScraper.extract_subtitles(video.youtube_url, language: language)

    if transcript.present?
      video.update!(transcript: transcript)
      Rails.logger.info("[ExtractTranscripts] [#{current}/#{total}] Transcript: #{transcript.length} chars")

      # Trigger pipeline: analyze with Claude + generate embeddings
      if pipeline
        Rails.logger.info("[ExtractTranscripts] [#{current}/#{total}] Queuing analysis+embedding...")
        ReanalyzeVideoJob.perform_async(video.id, true)
      end

      :success
    else
      Rails.logger.warn("[ExtractTranscripts] [#{current}/#{total}] No subtitles available")
      :no_subs
    end
  rescue StandardError => e
    Rails.logger.error("[ExtractTranscripts] [#{current}/#{total}] Failed: #{e.message}")
    :failed
  end
end
