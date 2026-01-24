# frozen_string_literal: true

class CreateYoutubeChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_channels do |t|
      t.string :channel_id, null: false       # YouTube channel ID (e.g., UCxxxxxxxx)
      t.string :handle, null: false           # @handle (e.g., superbeast1004)
      t.string :name, null: false             # Display name
      t.string :url, null: false              # Full URL
      t.text :description
      t.string :thumbnail_url
      t.integer :subscriber_count
      t.integer :video_count
      t.boolean :active, default: true        # Whether to analyze this channel
      t.datetime :last_synced_at              # Last time we synced videos
      t.datetime :last_analyzed_at            # Last time we analyzed videos

      t.timestamps
    end

    add_index :youtube_channels, :channel_id, unique: true
    add_index :youtube_channels, :handle, unique: true
    add_index :youtube_channels, :active
  end
end
