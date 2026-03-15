# frozen_string_literal: true

# Background job to backfill structured_transcript for existing videos.
# Re-fetches captions from YouTube in structured format (array of hashes).
#
# Usage:
#   BackfillStructuredTranscriptsJob.perform_async       # up to 100
#   BackfillStructuredTranscriptsJob.perform_async(50)   # 50 videos
#   BackfillStructuredTranscriptsJob.perform_async(50, "ko")  # Korean only
#
class BackfillStructuredTranscriptsJob
  include Sidekiq::Job

  sidekiq_options queue: :low, retry: 1

  def perform(limit = 100, language = nil)
    scope = YoutubeVideo.where.not(transcript: [nil, ""])
                        .where(structured_transcript: nil)
                        .joins(:youtube_channel)
                        .where(youtube_channels: { active: true })
    scope = scope.where(youtube_channels: { language: language }) if language.present?

    videos = scope.limit(limit).order(:id)
    total = videos.count
    Rails.logger.info("[BackfillStructured] Starting: #{total} videos")

    success = 0
    failed = 0

    videos.find_each.with_index do |video, index|
      url = video.youtube_url
      lang = video.youtube_channel&.language || "ko"

      structured = YoutubeChannelScraper.extract_structured_subtitles(url, language: lang)

      if structured.present?
        video.update!(structured_transcript: structured)
        success += 1
        Rails.logger.info("[BackfillStructured] [#{index + 1}/#{total}] #{video.title.truncate(40)} → #{structured.length} captions")
      else
        failed += 1
        Rails.logger.warn("[BackfillStructured] [#{index + 1}/#{total}] #{video.title.truncate(40)} → no subtitles")
      end

      sleep 2
    rescue StandardError => e
      failed += 1
      Rails.logger.error("[BackfillStructured] [#{index + 1}/#{total}] Failed: #{e.message}")
    end

    Rails.logger.info("[BackfillStructured] Complete: success=#{success}, failed=#{failed}")
  end
end
