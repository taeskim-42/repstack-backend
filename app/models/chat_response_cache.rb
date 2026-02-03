# frozen_string_literal: true

class ChatResponseCache < ApplicationRecord
  validates :question, presence: true
  validates :answer, presence: true

  SIMILARITY_THRESHOLD = 0.85
  CACHE_LIMIT = 10_000  # Max cached responses

  class << self
    # Find similar cached response using vector similarity
    def find_similar(question, threshold: SIMILARITY_THRESHOLD)
      return nil unless EmbeddingService.configured? && has_embedding_column?

      # Generate embedding for the question
      embedding = EmbeddingService.generate(question)
      return nil unless embedding

      # Search for similar questions using cosine similarity
      result = where.not(embedding: nil)
        .order(Arel.sql("embedding <=> '#{embedding}'"))
        .limit(1)
        .first

      return nil unless result

      # Calculate similarity (cosine distance to similarity)
      similarity = calculate_similarity(embedding, result.embedding)

      if similarity >= threshold
        result.increment!(:hit_count)
        Rails.logger.info("[ChatResponseCache] HIT! similarity=#{similarity.round(3)}, question=#{question[0..30]}...")
        result
      else
        Rails.logger.info("[ChatResponseCache] MISS similarity=#{similarity.round(3)} < #{threshold}")
        nil
      end
    end

    # Cache a new question-answer pair
    def cache_response(question:, answer:)
      return nil unless EmbeddingService.configured? && has_embedding_column?
      return nil if question.blank? || answer.blank? || question.length < 10

      # Check if similar question already exists
      existing = find_similar(question, threshold: 0.95)
      if existing
        Rails.logger.info("[ChatResponseCache] Similar question already cached, skipping")
        return existing
      end

      # Generate embedding
      embedding = EmbeddingService.generate(question)
      return nil unless embedding

      # Cleanup old entries if over limit
      cleanup_old_entries if count > CACHE_LIMIT

      create!(
        question: question,
        answer: answer,
        embedding: embedding
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[ChatResponseCache] Failed to cache: #{e.message}")
      nil
    end

    def has_embedding_column?
      column_names.include?("embedding")
    rescue
      false
    end

    private

    def calculate_similarity(embedding1, embedding2)
      return 0 unless embedding1 && embedding2

      # Convert to arrays if needed
      vec1 = embedding1.is_a?(Array) ? embedding1 : embedding1.to_a
      vec2 = embedding2.is_a?(Array) ? embedding2 : embedding2.to_a

      # Cosine similarity
      dot_product = vec1.zip(vec2).sum { |a, b| a * b }
      magnitude1 = Math.sqrt(vec1.sum { |x| x * x })
      magnitude2 = Math.sqrt(vec2.sum { |x| x * x })

      return 0 if magnitude1.zero? || magnitude2.zero?

      dot_product / (magnitude1 * magnitude2)
    end

    def cleanup_old_entries
      # Keep most frequently hit and recent entries
      delete_count = count - CACHE_LIMIT + 1000
      return if delete_count <= 0

      old_ids = order(hit_count: :asc, created_at: :asc)
        .limit(delete_count)
        .pluck(:id)

      where(id: old_ids).delete_all
      Rails.logger.info("[ChatResponseCache] Cleaned up #{old_ids.size} old entries")
    end
  end
end
