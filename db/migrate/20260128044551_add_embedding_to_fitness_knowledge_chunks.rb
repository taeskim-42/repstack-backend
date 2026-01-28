# frozen_string_literal: true

class AddEmbeddingToFitnessKnowledgeChunks < ActiveRecord::Migration[8.1]
  def up
    # Enable pgvector extension (Railway PostgreSQL supports this)
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Check if embedding column already exists
    unless column_exists?(:fitness_knowledge_chunks, :embedding)
      # Add embedding column with 768 dimensions (Gemini text-embedding-004)
      execute "ALTER TABLE fitness_knowledge_chunks ADD COLUMN embedding vector(768)"

      # Create index for vector similarity search
      execute <<-SQL
        CREATE INDEX IF NOT EXISTS index_knowledge_chunks_on_embedding
        ON fitness_knowledge_chunks
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100)
      SQL
    end
  end

  def down
    if column_exists?(:fitness_knowledge_chunks, :embedding)
      remove_index :fitness_knowledge_chunks, name: :index_knowledge_chunks_on_embedding, if_exists: true
      remove_column :fitness_knowledge_chunks, :embedding
    end
  end
end
