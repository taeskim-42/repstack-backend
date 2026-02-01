# frozen_string_literal: true

# Periodic job to generate embeddings for knowledge chunks that don't have them
class GeneratePendingEmbeddingsJob
  include Sidekiq::Job

  sidekiq_options queue: :video_analysis, retry: 1

  # @param batch_size [Integer] Number of chunks to process per run
  def perform(batch_size = 50)
    unless EmbeddingService.configured?
      Rails.logger.warn("[GeneratePendingEmbeddingsJob] OpenAI API not configured, skipping")
      return
    end

    unless EmbeddingService.pgvector_available?
      Rails.logger.warn("[GeneratePendingEmbeddingsJob] pgvector not available, skipping")
      return
    end

    # Find chunks without embeddings
    chunks = FitnessKnowledgeChunk
      .where(embedding: nil)
      .limit(batch_size)

    if chunks.empty?
      Rails.logger.info("[GeneratePendingEmbeddingsJob] No chunks need embeddings")
      return
    end

    Rails.logger.info("[GeneratePendingEmbeddingsJob] Processing #{chunks.count} chunks")

    success = 0
    failed = 0

    chunks.find_each do |chunk|
      EmbeddingService.embed_knowledge_chunk(chunk)
      success += 1
    rescue StandardError => e
      Rails.logger.error("[GeneratePendingEmbeddingsJob] Failed for chunk #{chunk.id}: #{e.message}")
      failed += 1
    end

    Rails.logger.info("[GeneratePendingEmbeddingsJob] Complete: #{success} success, #{failed} failed")
  end
end
