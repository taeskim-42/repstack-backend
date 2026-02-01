# frozen_string_literal: true

# Periodic job to process videos that have transcripts but haven't been analyzed
# Runs the full pipeline: Claude analysis → embeddings
class ProcessPendingVideosJob
  include Sidekiq::Job

  sidekiq_options queue: :video_analysis, retry: 1

  # @param batch_size [Integer] Number of videos to process per run
  def perform(batch_size = 10)
    # Find videos with transcript but not yet analyzed (or failed)
    videos = YoutubeVideo
      .where.not(transcript: [nil, ""])
      .where(analysis_status: %w[pending failed])
      .order(published_at: :desc)
      .limit(batch_size)

    if videos.empty?
      Rails.logger.info("[ProcessPendingVideosJob] No pending videos to process")
      return
    end

    Rails.logger.info("[ProcessPendingVideosJob] Processing #{videos.count} videos")

    videos.each do |video|
      # Skip transcript extraction since we already have it
      ReanalyzeVideoJob.perform_async(video.id, true)
    end

    Rails.logger.info("[ProcessPendingVideosJob] Enqueued #{videos.count} videos for analysis")
  end
end
