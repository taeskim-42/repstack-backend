# frozen_string_literal: true

# Service to extract video URLs from YouTube channels using yt-dlp
# No YouTube API key required
class YoutubeChannelScraper
  class YtDlpNotFoundError < StandardError; end
  class ScrapeError < StandardError; end

  class << self
    # Extract all video URLs from a channel
    def extract_video_urls(channel_url, limit: nil)
      ensure_yt_dlp_installed!

      # Normalize channel URL to videos page
      videos_url = normalize_channel_url(channel_url)

      # Build yt-dlp command as array to avoid shell escaping issues
      cmd_args = build_command_args(videos_url, limit)

      Rails.logger.info("Extracting videos from: #{videos_url}")

      output, status = Open3.capture2(*cmd_args)

      unless status.success?
        raise ScrapeError, "yt-dlp failed for #{channel_url}"
      end

      # Parse output - one URL per line
      urls = output.strip.split("\n").map(&:strip).reject(&:empty?)

      Rails.logger.info("Found #{urls.count} videos")
      urls
    end

    # Extract video metadata (URL, title, upload date) without downloading
    def extract_video_metadata(channel_url, limit: nil)
      ensure_yt_dlp_installed!

      videos_url = normalize_channel_url(channel_url)

      # Build command as array to avoid shell escaping issues
      cmd_args = [
        "yt-dlp",
        "--flat-playlist",
        "--print", "%(url)s|||%(title)s|||%(upload_date)s"
      ]
      cmd_args += ["--playlist-end", limit.to_s] if limit
      cmd_args << videos_url

      output, status = Open3.capture2(*cmd_args)

      unless status.success?
        raise ScrapeError, "yt-dlp failed for #{channel_url}"
      end

      output.strip.split("\n").map do |line|
        parts = line.split("|||")
        {
          url: parts[0],
          video_id: extract_video_id(parts[0]),
          title: parts[1],
          upload_date: parse_upload_date(parts[2])
        }
      end
    end

    # Get videos uploaded after a specific date
    def extract_new_videos(channel_url, since_date:, limit: 100)
      all_videos = extract_video_metadata(channel_url, limit: limit)

      all_videos.select do |video|
        video[:upload_date] && video[:upload_date] > since_date
      end
    end

    # Check if yt-dlp is installed
    def yt_dlp_installed?
      system("which yt-dlp > /dev/null 2>&1")
    end

    # Extract auto-generated subtitles from a video
    # Returns transcript text or nil if not available
    def extract_subtitles(video_url, language: "ko")
      ensure_yt_dlp_installed!

      # Create temp file for subtitle
      require "tempfile"
      temp_dir = Dir.mktmpdir("yt_subs")

      begin
        cmd_args = [
          "yt-dlp",
          "--write-auto-sub",
          "--sub-lang", language,
          "--sub-format", "srt",
          "--skip-download",
          "-o", "#{temp_dir}/sub",
          video_url
        ]

        _output, status = Open3.capture2(*cmd_args)

        unless status.success?
          Rails.logger.warn("Failed to extract subtitles for #{video_url}")
          return nil
        end

        # Find and read the subtitle file
        sub_file = Dir.glob("#{temp_dir}/sub.*.srt").first
        return nil unless sub_file && File.exist?(sub_file)

        # Parse SRT and extract plain text
        parse_srt_to_text(File.read(sub_file))
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    private

    # Convert SRT format to text with timestamps
    # Returns format: "[00:05] 텍스트 [00:10] 텍스트 ..."
    def parse_srt_to_text(srt_content)
      lines = []
      srt_content.split("\n\n").each do |block|
        block_lines = block.split("\n")
        next if block_lines.length < 3

        # Parse timestamp line (e.g., "00:00:05,000 --> 00:00:10,000")
        timestamp_line = block_lines[1]
        start_time = parse_srt_timestamp(timestamp_line)

        # Get text lines (skip sequence number and timestamp)
        text_lines = block_lines.drop(2)
        text = text_lines.join(" ").strip
        # Remove sound effects like [음악], [웃음]
        text = text.gsub(/\[.*?\]/, "").strip

        next if text.empty?

        # Include timestamp with text
        if start_time
          lines << "[#{format_seconds(start_time)}] #{text}"
        else
          lines << text
        end
      end
      lines.join(" ").gsub(/\s+/, " ").strip
    end

    # Parse SRT timestamp to seconds
    # Input: "00:01:30,500 --> 00:01:35,000"
    # Output: 90 (seconds)
    def parse_srt_timestamp(timestamp_line)
      return nil unless timestamp_line&.include?("-->")

      start_str = timestamp_line.split("-->").first.strip
      # Format: HH:MM:SS,mmm
      match = start_str.match(/(\d{2}):(\d{2}):(\d{2}),(\d{3})/)
      return nil unless match

      hours = match[1].to_i
      minutes = match[2].to_i
      seconds = match[3].to_i

      (hours * 3600) + (minutes * 60) + seconds
    end

    # Format seconds to MM:SS
    def format_seconds(total_seconds)
      minutes = total_seconds / 60
      seconds = total_seconds % 60
      format("%02d:%02d", minutes, seconds)
    end

    def ensure_yt_dlp_installed!
      return if yt_dlp_installed?

      raise YtDlpNotFoundError, "yt-dlp is not installed. Install with: brew install yt-dlp"
    end

    def normalize_channel_url(url)
      # Handle different channel URL formats
      if url.include?("/videos")
        url
      elsif url.include?("/@")
        "#{url}/videos"
      elsif url.include?("/channel/")
        "#{url}/videos"
      else
        "#{url}/videos"
      end
    end

    def build_command_args(url, limit)
      args = [
        "yt-dlp",
        "--flat-playlist",
        "--print", "url"
      ]

      args += ["--playlist-end", limit.to_s] if limit

      args << url

      args
    end

    def extract_video_id(url)
      return nil unless url

      if url.include?("watch?v=")
        url.split("watch?v=").last.split("&").first
      elsif url.include?("youtu.be/")
        url.split("youtu.be/").last.split("?").first
      else
        url
      end
    end

    def parse_upload_date(date_str)
      return nil if date_str.nil? || date_str == "NA" || date_str.empty?

      Date.strptime(date_str, "%Y%m%d")
    rescue ArgumentError
      nil
    end
  end
end
