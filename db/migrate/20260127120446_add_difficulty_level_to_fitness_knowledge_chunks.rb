# frozen_string_literal: true

class AddDifficultyLevelToFitnessKnowledgeChunks < ActiveRecord::Migration[8.0]
  def change
    add_column :fitness_knowledge_chunks, :difficulty_level, :string, default: "all"
    add_index :fitness_knowledge_chunks, :difficulty_level
  end
end
