# frozen_string_literal: true

class ChangeEmbeddingToOpenaiDimension < ActiveRecord::Migration[8.1]
  def up
    # Drop existing embedding column and index
    if column_exists?(:fitness_knowledge_chunks, :embedding)
      execute "DROP INDEX IF EXISTS index_knowledge_chunks_on_embedding"
      remove_column :fitness_knowledge_chunks, :embedding
    end

    # Add embedding column with 1536 dimensions (OpenAI text-embedding-3-small)
    execute "ALTER TABLE fitness_knowledge_chunks ADD COLUMN embedding vector(1536)"

    # Create index for vector similarity search
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS index_knowledge_chunks_on_embedding
      ON fitness_knowledge_chunks
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100)
    SQL
  end

  def down
    if column_exists?(:fitness_knowledge_chunks, :embedding)
      execute "DROP INDEX IF EXISTS index_knowledge_chunks_on_embedding"
      remove_column :fitness_knowledge_chunks, :embedding
    end

    # Restore 768-dimension column (Gemini)
    execute "ALTER TABLE fitness_knowledge_chunks ADD COLUMN embedding vector(768)"
  end
end
