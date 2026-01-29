# frozen_string_literal: true

# Background job to extract transcripts and trigger full pipeline
# Pipeline: transcript → Claude analysis → embeddings
#
# Usage:
#   ExtractTranscriptsJob.perform_async          # Process all (up to 100)
#   ExtractTranscriptsJob.perform_async(50)      # Process 50 videos
#   ExtractTranscriptsJob.perform_async(50, true, "en") # English only
#   ExtractTranscriptsJob.perform_async(50, true, nil, 123) # Specific channel
#
class ExtractTranscriptsJob
  include Sidekiq::Job

  sidekiq_options queue: :low, retry: 1

  # Process videos without transcripts
  # @param limit [Integer] Maximum number of videos to process (default: 100)
  # @param pipeline [Boolean] If true, trigger analysis + embedding after transcript (default: true)
  # @param language [String] Filter by channel language: "en", "ko", or nil for all
  # @param channel_id [Integer] Filter by specific channel ID for parallel processing
  def perform(limit = 100, pipeline = true, language = nil, channel_id = nil)
    scope = YoutubeVideo.where(transcript: [nil, ""])

    # Filter by specific channel (for parallel processing)
    if channel_id.present?
      scope = scope.where(youtube_channel_id: channel_id)
    elsif language.present?
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

      # Rate limiting: 2 seconds between requests (youtube-transcript-rb is lighter)
      sleep 2
    end

    Rails.logger.info(
      "[ExtractTranscripts] Complete: success=#{success}, no_subs=#{no_subs}, failed=#{failed}"
    )

    # Auto-continue: if there are more videos for this channel/language, queue the next batch
    remaining_scope = YoutubeVideo.where(transcript: [nil, ""])
    if channel_id.present?
      remaining_scope = remaining_scope.where(youtube_channel_id: channel_id)
      channel_name = YoutubeChannel.find_by(id: channel_id)&.name || channel_id
    elsif language.present?
      remaining_scope = remaining_scope.joins(:youtube_channel).where(youtube_channels: { language: language })
      channel_name = language
    else
      channel_name = "all"
    end
    remaining = remaining_scope.count

    if remaining > 0
      Rails.logger.info("[ExtractTranscripts] #{remaining} videos remaining for #{channel_name}, queuing next batch...")
      ExtractTranscriptsJob.perform_in(5.seconds, limit, pipeline, language, channel_id)
    else
      Rails.logger.info("[ExtractTranscripts] Complete for #{channel_name}!")
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
