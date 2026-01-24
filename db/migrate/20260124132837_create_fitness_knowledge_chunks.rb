# frozen_string_literal: true

class CreateFitnessKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :fitness_knowledge_chunks do |t|
      t.references :youtube_video, null: false, foreign_key: true

      # Knowledge type: exercise_technique, routine_design, nutrition_recovery, form_check
      t.string :knowledge_type, null: false

      # Content
      t.text :content, null: false            # The actual knowledge text
      t.text :summary                         # Brief summary for display
      t.jsonb :metadata, default: {}          # Additional structured data

      # For exercise techniques
      t.string :exercise_name                 # e.g., "bench press", "squat"
      t.string :muscle_group                  # e.g., "chest", "legs"
      t.string :difficulty_level              # beginner, intermediate, advanced

      # Source reference
      t.integer :timestamp_start              # Video timestamp (seconds)
      t.integer :timestamp_end

      t.timestamps
    end

    add_index :fitness_knowledge_chunks, :knowledge_type
    add_index :fitness_knowledge_chunks, :exercise_name
    add_index :fitness_knowledge_chunks, :muscle_group

    # Vector embedding column (only if pgvector is available)
    if pgvector_available?
      add_column :fitness_knowledge_chunks, :embedding, "vector(1536)"

      # Vector similarity index (for RAG queries)
      execute <<-SQL
        CREATE INDEX index_knowledge_chunks_on_embedding
        ON fitness_knowledge_chunks
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100);
      SQL
    else
      puts "WARNING: pgvector not available - embedding column not created"
      puts "RAG search will fall back to keyword-based search"
    end
  end

  private

  def pgvector_available?
    result = execute("SELECT * FROM pg_extension WHERE extname = 'vector'")
    result.any?
  rescue StandardError
    false
  end
end
