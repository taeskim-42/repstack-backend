# frozen_string_literal: true

# Job to process a single YouTube video: analyze with Claude + generate embeddings
# Full pipeline: transcript → Claude analysis → embeddings
class ReanalyzeVideoJob
  include Sidekiq::Job

  sidekiq_options queue: :video_analysis, retry: 2

  # @param video_id [Integer] Video ID to process
  # @param skip_transcript [Boolean] Skip transcript extraction (default: false)
  def perform(video_id, skip_transcript = false)
    video = YoutubeVideo.find_by(id: video_id)
    return unless video

    Rails.logger.info("[ReanalyzeVideoJob] Starting for video #{video_id}: #{video.title.truncate(50)}")

    # Step 1: Extract transcript if not present
    unless skip_transcript
      if video.transcript.blank?
        Rails.logger.info("[ReanalyzeVideoJob] Extracting transcript...")
        transcript = YoutubeChannelScraper.extract_subtitles(video.youtube_url)

        if transcript.blank?
          Rails.logger.warn("[ReanalyzeVideoJob] No transcript available")
          video.update!(analysis_status: "failed", analysis_error: "No transcript available")
          return
        end

        video.update!(transcript: transcript)
        Rails.logger.info("[ReanalyzeVideoJob] Transcript saved: #{transcript.length} chars")
      end
    end

    # Step 2: Delete existing chunks and analyze with Claude
    video.fitness_knowledge_chunks.destroy_all
    video.update!(analysis_status: "pending", analysis_error: nil)

    YoutubeKnowledgeExtractionService.analyze_video(video)
    chunks_count = video.fitness_knowledge_chunks.count
    Rails.logger.info("[ReanalyzeVideoJob] Claude analysis complete: #{chunks_count} chunks")

    # Step 3: Generate embeddings for all chunks
    if EmbeddingService.configured? && EmbeddingService.pgvector_available?
      embedded_count = 0
      video.fitness_knowledge_chunks.find_each do |chunk|
        EmbeddingService.embed_knowledge_chunk(chunk)
        embedded_count += 1
      rescue StandardError => e
        Rails.logger.error("[ReanalyzeVideoJob] Embedding failed for chunk #{chunk.id}: #{e.message}")
      end
      Rails.logger.info("[ReanalyzeVideoJob] Embeddings generated: #{embedded_count}/#{chunks_count}")
    else
      Rails.logger.warn("[ReanalyzeVideoJob] Embedding skipped (not configured or pgvector unavailable)")
    end

    Rails.logger.info("[ReanalyzeVideoJob] Complete for video #{video_id}")
  rescue StandardError => e
    Rails.logger.error("[ReanalyzeVideoJob] Failed for video #{video_id}: #{e.message}")
    raise
  end
end
