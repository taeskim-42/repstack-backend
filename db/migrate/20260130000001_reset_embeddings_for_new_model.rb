# frozen_string_literal: true

class ResetEmbeddingsForNewModel < ActiveRecord::Migration[8.1]
  def up
    # Reset embeddings to regenerate with text-embedding-3-large model
    # The dimension stays at 1536, but the model produces better quality embeddings
    if column_exists?(:fitness_knowledge_chunks, :embedding)
      execute "UPDATE fitness_knowledge_chunks SET embedding = NULL"
    end
  end

  def down
    # Cannot restore old embeddings
  end
end
