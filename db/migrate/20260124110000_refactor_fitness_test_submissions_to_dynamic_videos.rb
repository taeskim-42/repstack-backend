# frozen_string_literal: true

class RefactorFitnessTestSubmissionsToDynamicVideos < ActiveRecord::Migration[8.1]
  def change
    # Remove hardcoded columns
    remove_column :fitness_test_submissions, :pushup_video_key, :string
    remove_column :fitness_test_submissions, :squat_video_key, :string
    remove_column :fitness_test_submissions, :pullup_video_key, :string
    remove_column :fitness_test_submissions, :pushup_analysis, :jsonb
    remove_column :fitness_test_submissions, :squat_analysis, :jsonb
    remove_column :fitness_test_submissions, :pullup_analysis, :jsonb

    # Add dynamic arrays
    add_column :fitness_test_submissions, :videos, :jsonb, default: [], null: false
    add_column :fitness_test_submissions, :analyses, :jsonb, default: {}, null: false
  end
end
