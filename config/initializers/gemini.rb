# frozen_string_literal: true

# Gemini API Configuration
# Used for YouTube video analysis and knowledge extraction

module GeminiConfig
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta"
  UPLOAD_API_URL = "https://generativelanguage.googleapis.com/upload/v1beta"

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

    def upload_client
      @upload_client ||= Faraday.new do |conn|
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 600 # 10 minutes for large video uploads
        conn.options.open_timeout = 30
      end
    end

    # Generate content using Gemini API
    def generate_content(prompt:, video_url: nil, youtube_url: nil, video_data: nil, mime_type: nil, system_instruction: nil)
      raise "Gemini API key not configured" unless configured?

      contents = build_contents(prompt, video_url: video_url, youtube_url: youtube_url,
                                        video_data: video_data, mime_type: mime_type)
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

    # Upload a video file to Gemini File API
    # Returns file URI that can be used in generateContent
    # @param video_data [String] Binary video data
    # @param mime_type [String] MIME type (e.g., "video/mp4")
    # @param display_name [String] Optional display name
    def upload_video(video_data:, mime_type: "video/mp4", display_name: nil)
      raise "Gemini API key not configured" unless configured?

      display_name ||= "video_#{Time.current.to_i}"

      # Step 1: Initiate resumable upload
      init_url = "#{UPLOAD_API_URL}/files?key=#{api_key}"
      init_response = upload_client.post(init_url) do |req|
        req.headers["X-Goog-Upload-Protocol"] = "resumable"
        req.headers["X-Goog-Upload-Command"] = "start"
        req.headers["X-Goog-Upload-Header-Content-Length"] = video_data.bytesize.to_s
        req.headers["X-Goog-Upload-Header-Content-Type"] = mime_type
        req.headers["Content-Type"] = "application/json"
        req.body = { file: { display_name: display_name } }.to_json
      end

      upload_url = init_response.headers["x-goog-upload-url"]
      raise "Failed to initiate upload: #{init_response.body}" unless upload_url

      # Step 2: Upload the actual bytes
      upload_response = upload_client.post(upload_url) do |req|
        req.headers["X-Goog-Upload-Command"] = "upload, finalize"
        req.headers["X-Goog-Upload-Offset"] = "0"
        req.headers["Content-Type"] = mime_type
        req.body = video_data
      end

      unless upload_response.success?
        raise "Failed to upload video: #{upload_response.body}"
      end

      result = JSON.parse(upload_response.body)
      file_uri = result.dig("file", "uri")
      file_name = result.dig("file", "name")

      Rails.logger.info("[GeminiConfig] Video uploaded: #{file_name}, URI: #{file_uri}")

      # Wait for file to be processed
      wait_for_file_processing(file_name)

      { file_uri: file_uri, file_name: file_name }
    end

    # Analyze an uploaded video file
    # @param video_data [String] Binary video data
    # @param mime_type [String] MIME type
    # @param prompt [String] Analysis prompt
    # @param system_instruction [String] Optional system instruction
    def analyze_uploaded_video(video_data:, mime_type: "video/mp4", prompt:, system_instruction: nil)
      # Upload the video first
      upload_result = upload_video(video_data: video_data, mime_type: mime_type)

      # Generate content with the uploaded file
      contents = [{
        parts: [
          { file_data: { mime_type: mime_type, file_uri: upload_result[:file_uri] } },
          { text: prompt }
        ]
      }]

      body = { contents: contents }
      body[:system_instruction] = { parts: [{ text: system_instruction }] } if system_instruction

      full_url = "#{GEMINI_API_URL}/models/#{model}:generateContent?key=#{api_key}"
      response = client.post(full_url, body)

      handle_response(response)
    end

    private

    def wait_for_file_processing(file_name, max_wait: 60)
      start_time = Time.current

      loop do
        status_url = "#{GEMINI_API_URL}/#{file_name}?key=#{api_key}"
        response = client.get(status_url)

        if response.success?
          data = response.body.is_a?(String) ? JSON.parse(response.body) : response.body
          state = data["state"]

          return if state == "ACTIVE"

          if state == "FAILED"
            raise "File processing failed: #{data['error']}"
          end
        end

        if Time.current - start_time > max_wait
          raise "File processing timeout after #{max_wait} seconds"
        end

        sleep 2
      end
    end

    def build_contents(prompt, video_url: nil, youtube_url: nil, video_data: nil, mime_type: nil)
      parts = []

      # Support direct YouTube URL (Gemini can fetch and analyze)
      if youtube_url.present?
        parts << {
          file_data: {
            mime_type: "video/*",
            file_uri: youtube_url
          }
        }
      elsif video_data.present?
        # Base64 inline data for small videos
        parts << {
          inline_data: {
            mime_type: mime_type || "video/mp4",
            data: Base64.strict_encode64(video_data)
          }
        }
      elsif video_url.present?
        # For pre-uploaded files (file_uri from Gemini File API)
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
