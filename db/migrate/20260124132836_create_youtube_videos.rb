# frozen_string_literal: true

class CreateYoutubeVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_videos do |t|
      t.references :youtube_channel, null: false, foreign_key: true

      t.string :video_id, null: false         # YouTube video ID (11 chars)
      t.string :title, null: false
      t.text :description
      t.string :thumbnail_url
      t.integer :duration_seconds             # Video length in seconds
      t.integer :view_count
      t.integer :like_count
      t.datetime :published_at                # Video publish date

      # Analysis status
      t.string :analysis_status, default: "pending"  # pending, analyzing, completed, failed
      t.datetime :analyzed_at
      t.text :analysis_error

      # Raw analysis result from Gemini
      t.jsonb :raw_analysis, default: {}

      # Extracted metadata
      t.string :language                      # Detected language
      t.string :category                      # Fitness category (strength, cardio, etc.)
      t.string :difficulty_level              # beginner, intermediate, advanced
      t.text :transcript                      # Auto-generated transcript if available

      t.timestamps
    end

    add_index :youtube_videos, :video_id, unique: true
    add_index :youtube_videos, :analysis_status
    add_index :youtube_videos, :published_at
    add_index :youtube_videos, :category
  end
end
