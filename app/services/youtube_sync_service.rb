# frozen_string_literal: true

# Service to sync videos from YouTube channels using yt-dlp
# No YouTube API key required
class YoutubeSyncService
  class << self
    def sync_all_channels
      YoutubeChannel.active.find_each do |channel|
        sync_channel(channel)
      end
    end

    def sync_channel(channel, limit: 100)
      Rails.logger.info("Syncing YouTube channel: #{channel.name}")

      begin
        # Use yt-dlp to get video metadata
        videos_data = YoutubeChannelScraper.extract_video_metadata(channel.url, limit: limit)

        videos_data.each do |video_data|
          create_or_update_video(channel, video_data)
        end

        channel.mark_synced!

        Rails.logger.info("Successfully synced #{channel.name}: #{videos_data.count} videos")
        videos_data.count
      rescue YoutubeChannelScraper::YtDlpNotFoundError => e
        Rails.logger.error("yt-dlp not installed: #{e.message}")
        raise
      rescue StandardError => e
        Rails.logger.error("Failed to sync channel #{channel.name}: #{e.message}")
        raise
      end
    end

    def sync_new_videos_only(channel, since: nil)
      since ||= channel.last_synced_at || 1.month.ago

      Rails.logger.info("Syncing new videos from #{channel.name} since #{since}")

      begin
        new_videos = YoutubeChannelScraper.extract_new_videos(
          channel.url,
          since_date: since.to_date,
          limit: 50
        )

        new_videos.each do |video_data|
          create_or_update_video(channel, video_data)
        end

        channel.mark_synced!

        Rails.logger.info("Found #{new_videos.count} new videos")
        new_videos.count
      rescue StandardError => e
        Rails.logger.error("Failed to sync new videos for #{channel.name}: #{e.message}")
        0
      end
    end

    private

    def create_or_update_video(channel, video_data)
      video = channel.youtube_videos.find_or_initialize_by(video_id: video_data[:video_id])

      video.assign_attributes(
        title: video_data[:title] || "Untitled",
        published_at: video_data[:upload_date]
      )

      video.save!
      video
    rescue StandardError => e
      Rails.logger.warn("Could not save video #{video_data[:video_id]}: #{e.message}")
      nil
    end
  end
end
