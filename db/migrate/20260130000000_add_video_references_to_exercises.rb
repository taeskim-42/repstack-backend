# frozen_string_literal: true

class AddVideoReferencesToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :video_references, :jsonb, default: [], null: false

    # Add GIN index for efficient JSONB queries
    add_index :exercises, :video_references, using: :gin
  end
end
