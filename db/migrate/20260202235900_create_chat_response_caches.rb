# frozen_string_literal: true

class CreateChatResponseCaches < ActiveRecord::Migration[7.1]
  def change
    create_table :chat_response_caches do |t|
      t.text :question, null: false
      t.text :answer, null: false
      t.vector :embedding, limit: 1536
      t.integer :hit_count, default: 0
      t.timestamps
    end

    add_index :chat_response_caches, :created_at

    # Add HNSW index for fast similarity search (if pgvector supports it)
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS chat_response_caches_embedding_idx
      ON chat_response_caches
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100);
    SQL
  end
end
