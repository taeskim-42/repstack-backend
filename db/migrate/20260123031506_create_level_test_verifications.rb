# frozen_string_literal: true

class CreateLevelTestVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :level_test_verifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :test_id, null: false
      t.integer :current_level, null: false
      t.integer :target_level, null: false
      t.string :status, null: false, default: 'pending' # pending, passed, failed

      # Exercise verification results (stored as JSON)
      t.jsonb :exercises, null: false, default: []

      # Overall results
      t.boolean :passed, default: false
      t.integer :new_level
      t.text :ai_feedback

      # Timestamps
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :level_test_verifications, :test_id, unique: true
    add_index :level_test_verifications, [:user_id, :status]
    add_index :level_test_verifications, :created_at
  end
end
