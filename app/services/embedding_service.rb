# frozen_string_literal: true

# Service to generate text embeddings using OpenAI API
# Used for RAG (Retrieval Augmented Generation) functionality
class EmbeddingService
  OPENAI_EMBEDDING_URL = "https://api.openai.com/v1/embeddings"
  EMBEDDING_MODEL = "text-embedding-3-small"
  EMBEDDING_DIMENSION = 1536  # OpenAI text-embedding-3-small dimension

  class << self
    def configured?
      ENV["OPENAI_API_KEY"].present?
    end

    def generate(text)
      raise "OpenAI API key not configured" unless configured?
      return nil if text.blank?

      response = client.post(OPENAI_EMBEDDING_URL) do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
        req.body = {
          model: EMBEDDING_MODEL,
          input: sanitize_text(text)
        }.to_json
      end

      handle_response(response)
    end

    def generate_batch(texts, batch_size: 20)
      raise "OpenAI API key not configured" unless configured?
      return [] if texts.empty?

      # OpenAI supports batch embedding
      response = client.post(OPENAI_EMBEDDING_URL) do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
        req.body = {
          model: EMBEDDING_MODEL,
          input: texts.map { |t| sanitize_text(t) }
        }.to_json
      end

      if response.success?
        response.body["data"]&.map { |d| d["embedding"] } || []
      else
        Rails.logger.error("OpenAI Embedding batch error: #{response.body}")
        []
      end
    end

    # Generate and save embedding for a knowledge chunk
    def embed_knowledge_chunk(chunk)
      return unless pgvector_available?

      text = build_chunk_text(chunk)
      embedding = generate(text)

      chunk.update!(embedding: embedding) if embedding
      embedding
    end

    # Generate embeddings for all chunks without embeddings
    def embed_all_pending_chunks(limit: 100)
      return unless pgvector_available? && configured?

      chunks = FitnessKnowledgeChunk.where(embedding: nil).limit(limit)

      chunks.find_each do |chunk|
        embed_knowledge_chunk(chunk)
      rescue StandardError => e
        Rails.logger.error("Failed to embed chunk #{chunk.id}: #{e.message}")
      end
    end

    # Generate embedding for a query (for RAG search)
    def generate_query_embedding(query)
      generate(query)
    end

    def pgvector_available?
      FitnessKnowledgeChunk.column_names.include?("embedding")
    end

    private

    def client
      @client ||= Faraday.new do |conn|
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 60
        conn.options.open_timeout = 10
      end
    end

    def sanitize_text(text)
      # Truncate to avoid token limits
      text.to_s.truncate(30_000)
    end

    def build_chunk_text(chunk)
      parts = []
      parts << "#{chunk.knowledge_type.humanize}:"
      parts << chunk.summary if chunk.summary.present?
      parts << chunk.content
      parts << "운동: #{chunk.exercise_name}" if chunk.exercise_name.present?
      parts << "근육: #{chunk.muscle_group}" if chunk.muscle_group.present?

      parts.join(" ")
    end

    def handle_response(response)
      if response.success?
        data = response.body
        data.dig("data", 0, "embedding")
      else
        error_message = response.body.dig("error", "message") || response.body.to_s
        Rails.logger.error("OpenAI Embedding API error: #{error_message}")
        nil
      end
    end
  end
end
