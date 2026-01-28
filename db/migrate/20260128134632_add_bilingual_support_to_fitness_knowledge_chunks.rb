class AddBilingualSupportToFitnessKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    add_column :fitness_knowledge_chunks, :content_original, :text
    add_column :fitness_knowledge_chunks, :language, :string, default: "ko", null: false
    add_index :fitness_knowledge_chunks, :language
  end
end
