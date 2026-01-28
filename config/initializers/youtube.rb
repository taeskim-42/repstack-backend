# frozen_string_literal: true

# YouTube Channel Configuration
# Videos are fetched using yt-dlp (no API key required)

module YoutubeConfig
  # Configured fitness YouTube channels for knowledge extraction
  CHANNELS = [
    # Korean channels
    {
      handle: "superbeast1004",
      name: "SuperBeast",
      url: "https://www.youtube.com/@superbeast1004",
      language: "ko"
    },
    {
      handle: "chulsoonofficial",
      name: "Chul Soon",
      url: "https://www.youtube.com/@chulsoonofficial",
      language: "ko"
    },
    {
      handle: "user-2001mr.koreachampion",
      name: "Korea Champion",
      url: "https://www.youtube.com/@user-2001mr.koreachampion",
      language: "ko"
    },
    # English channels
    {
      handle: "jeffnippard",
      name: "Jeff Nippard",
      url: "https://www.youtube.com/@jeffnippard",
      language: "en"
    },
    {
      handle: "jeremyethier",
      name: "Jeremy Ethier",
      url: "https://www.youtube.com/@jeremyethier",
      language: "en"
    },
    {
      handle: "RenaissancePeriodization",
      name: "Renaissance Periodization",
      url: "https://www.youtube.com/@RenaissancePeriodization",
      language: "en"
    },
    {
      handle: "athleanx",
      name: "ATHLEAN-X",
      url: "https://www.youtube.com/@athleanx",
      language: "en"
    },
    {
      handle: "squatuniversity",
      name: "Squat University",
      url: "https://www.youtube.com/@squatuniversity",
      language: "en"
    },
    {
      handle: "MorePlatesMoreDates",
      name: "More Plates More Dates",
      url: "https://www.youtube.com/@MorePlatesMoreDates",
      language: "en"
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
