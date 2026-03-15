class AddStructuredTranscriptToYoutubeVideos < ActiveRecord::Migration[8.1]
  def change
    add_column :youtube_videos, :structured_transcript, :jsonb
  end
end
