# frozen_string_literal: true

# Gemini API Configuration
# Used for YouTube video analysis and knowledge extraction

module GeminiConfig
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta"

  class << self
    def api_key
      ENV["GEMINI_API_KEY"]
    end

    def configured?
      api_key.present?
    end

    def model
      # gemini-2.0-flash for video analysis (supports multimodal)
      ENV.fetch("GEMINI_MODEL", "gemini-2.0-flash")
    end

    def client
      @client ||= Faraday.new do |conn|
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 300 # 5 minutes for video analysis
        conn.options.open_timeout = 30
      end
    end

    # Generate content using Gemini API
    def generate_content(prompt:, video_url: nil, youtube_url: nil, system_instruction: nil)
      raise "Gemini API key not configured" unless configured?

      contents = build_contents(prompt, video_url: video_url, youtube_url: youtube_url)
      body = { contents: contents }
      body[:system_instruction] = { parts: [{ text: system_instruction }] } if system_instruction

      # Use full URL to avoid Faraday path joining issues with colons
      full_url = "#{GEMINI_API_URL}/models/#{model}:generateContent?key=#{api_key}"
      response = client.post(full_url, body)

      handle_response(response)
    end

    # Analyze a YouTube video directly by URL
    def analyze_youtube_video(youtube_url:, prompt:, system_instruction: nil)
      generate_content(
        prompt: prompt,
        youtube_url: youtube_url,
        system_instruction: system_instruction
      )
    end

    private

    def build_contents(prompt, video_url: nil, youtube_url: nil)
      parts = []

      # Support direct YouTube URL (Gemini can fetch and analyze)
      if youtube_url.present?
        parts << {
          file_data: {
            mime_type: "video/*",
            file_uri: youtube_url
          }
        }
      elsif video_url.present?
        parts << {
          file_data: {
            mime_type: "video/mp4",
            file_uri: video_url
          }
        }
      end

      parts << { text: prompt }

      [{ parts: parts }]
    end

    def handle_response(response)
      # Parse body if it's a string
      data = response.body.is_a?(String) ? JSON.parse(response.body) : response.body

      if response.success?
        if data["candidates"]&.first&.dig("content", "parts")&.first
          data["candidates"].first["content"]["parts"].first["text"]
        else
          raise "Unexpected Gemini API response format: #{data}"
        end
      else
        error_message = data.dig("error", "message") || data.to_s
        raise "Gemini API error (#{response.status}): #{error_message}"
      end
    end
  end
end
