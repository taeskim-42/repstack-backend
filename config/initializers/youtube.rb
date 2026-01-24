# frozen_string_literal: true

# YouTube Channel Configuration
# Videos are fetched using yt-dlp (no API key required)

module YoutubeConfig
  # Configured fitness YouTube channels for knowledge extraction
  CHANNELS = [
    {
      handle: "superbeast1004",
      name: "SuperBeast",
      url: "https://www.youtube.com/@superbeast1004"
    },
    {
      handle: "chulsoonofficial",
      name: "Chul Soon",
      url: "https://www.youtube.com/@chulsoonofficial"
    },
    {
      handle: "user-2001mr.koreachampion",
      name: "Korea Champion",
      url: "https://www.youtube.com/@user-2001mr.koreachampion"
    }
  ].freeze

  class << self
    def channels
      CHANNELS
    end

    # yt-dlp must be installed for video syncing
    def yt_dlp_available?
      YoutubeChannelScraper.yt_dlp_installed?
    end
  end
end
