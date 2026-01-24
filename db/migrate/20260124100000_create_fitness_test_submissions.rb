# frozen_string_literal: true

class CreateFitnessTestSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :fitness_test_submissions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :job_id, null: false, index: { unique: true }
      t.string :status, null: false, default: "pending"

      # Video keys (S3 paths)
      t.string :pushup_video_key
      t.string :squat_video_key
      t.string :pullup_video_key

      # Analysis results for each exercise
      t.jsonb :pushup_analysis, default: {}
      t.jsonb :squat_analysis, default: {}
      t.jsonb :pullup_analysis, default: {}

      # Final evaluation results
      t.integer :fitness_score
      t.integer :assigned_level
      t.string :assigned_tier
      t.jsonb :evaluation_result, default: {}

      # Error handling
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :fitness_test_submissions, :status
    add_index :fitness_test_submissions, [:user_id, :created_at]
  end
end
