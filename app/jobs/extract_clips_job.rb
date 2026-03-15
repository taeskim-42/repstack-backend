# frozen_string_literal: true

# Background job to extract exercise video clips from structured transcripts.
# Uses ExerciseClipExtractionService (Claude) to identify exercise segments.
#
# Usage:
#   ExtractClipsJob.perform_async          # Process all (up to 50)
#   ExtractClipsJob.perform_async(20)      # Process 20 videos
#
class ExtractClipsJob
  include Sidekiq::Job

  sidekiq_options queue: :video_analysis, retry: 1

  def perform(limit = 50)
    videos = YoutubeVideo
      .where.not(structured_transcript: nil)
      .left_joins(:exercise_video_clips)
      .where(exercise_video_clips: { id: nil })
      .limit(limit)
      .order(:id)

    total = videos.count
    Rails.logger.info("[ExtractClips] Starting: #{total} videos")

    success = 0
    failed = 0

    videos.find_each.with_index do |video, index|
      Rails.logger.info("[ExtractClips] [#{index + 1}/#{total}] #{video.title.truncate(50)}")

      clips = ExerciseClipExtractionService.extract(video)
      Rails.logger.info("[ExtractClips] [#{index + 1}/#{total}] Extracted #{clips.length} clips")
      success += 1
    rescue StandardError => e
      Rails.logger.error("[ExtractClips] [#{index + 1}/#{total}] Failed: #{e.message}")
      failed += 1
    end

    Rails.logger.info("[ExtractClips] Complete: success=#{success}, failed=#{failed}")
    { success: success, failed: failed }
  end
end
