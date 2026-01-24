# frozen_string_literal: true

class ChangeEmbeddingDimensionTo768 < ActiveRecord::Migration[8.1]
  def up
    # Only modify if pgvector is available and column exists
    return unless column_exists?(:fitness_knowledge_chunks, :embedding)

    # Drop old index and column, recreate with new dimension
    remove_index :fitness_knowledge_chunks, name: :index_knowledge_chunks_on_embedding, if_exists: true
    remove_column :fitness_knowledge_chunks, :embedding

    add_column :fitness_knowledge_chunks, :embedding, "vector(768)"

    execute <<-SQL
      CREATE INDEX index_knowledge_chunks_on_embedding
      ON fitness_knowledge_chunks
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100);
    SQL
  end

  def down
    return unless column_exists?(:fitness_knowledge_chunks, :embedding)

    remove_index :fitness_knowledge_chunks, name: :index_knowledge_chunks_on_embedding, if_exists: true
    remove_column :fitness_knowledge_chunks, :embedding

    add_column :fitness_knowledge_chunks, :embedding, "vector(1536)"

    execute <<-SQL
      CREATE INDEX index_knowledge_chunks_on_embedding
      ON fitness_knowledge_chunks
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100);
    SQL
  end
end
