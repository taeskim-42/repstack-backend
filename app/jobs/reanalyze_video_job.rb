# frozen_string_literal: true

# Job to reanalyze a single YouTube video with timestamp extraction
class ReanalyzeVideoJob
  include Sidekiq::Job

  sidekiq_options queue: :video_analysis, retry: 2

  def perform(video_id)
    video = YoutubeVideo.find_by(id: video_id)
    return unless video

    Rails.logger.info("[ReanalyzeVideoJob] Starting reanalysis for video #{video_id}: #{video.title}")

    # Delete existing chunks
    video.fitness_knowledge_chunks.destroy_all

    # Reset status to pending
    video.update!(analysis_status: "pending", analysis_error: nil)

    # Re-analyze with new timestamp extraction
    YoutubeKnowledgeExtractionService.analyze_video(video)

    Rails.logger.info("[ReanalyzeVideoJob] Completed reanalysis for video #{video_id}")
  rescue StandardError => e
    Rails.logger.error("[ReanalyzeVideoJob] Failed for video #{video_id}: #{e.message}")
    raise
  end
end
