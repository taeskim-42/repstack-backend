# frozen_string_literal: true

class AddDifficultyLevelToFitnessKnowledgeChunks < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:fitness_knowledge_chunks, :difficulty_level)
      add_column :fitness_knowledge_chunks, :difficulty_level, :string, default: "all"
    end

    unless index_exists?(:fitness_knowledge_chunks, :difficulty_level)
      add_index :fitness_knowledge_chunks, :difficulty_level
    end
  end
end
