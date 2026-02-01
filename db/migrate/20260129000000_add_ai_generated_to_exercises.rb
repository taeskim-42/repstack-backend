# frozen_string_literal: true

class AddAiGeneratedToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :ai_generated, :boolean, default: false
    add_index :exercises, :ai_generated
  end
end
