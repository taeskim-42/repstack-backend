# frozen_string_literal: true

# Service for interacting with App Store Connect API
# Handles JWT authentication and beta feedback retrieval
class AppStoreConnectService
  ASC_API_BASE = "https://api.appstoreconnect.apple.com"
  TOKEN_LIFETIME = 20 * 60 # 20 minutes

  class << self
    # Fetch new TestFlight beta feedback since last poll
    # @return [Array<Hash>] Array of feedback data
    def fetch_new_feedback
      unless configured?
        Rails.logger.warn("[AppStoreConnect] Not configured - missing environment variables")
        return []
      end

      token = generate_jwt
      feedbacks = fetch_beta_feedback(token)
      filter_new_feedbacks(feedbacks)
    rescue StandardError => e
      Rails.logger.error("[AppStoreConnect] Error fetching feedback: #{e.message}")
      []
    end

    def configured?
      ENV["ASC_KEY_ID"].present? &&
        ENV["ASC_ISSUER_ID"].present? &&
        ENV["ASC_PRIVATE_KEY"].present? &&
        ENV["ASC_APP_ID"].present?
    end

    # Backfill screenshots for existing feedbacks that have empty screenshots
    def backfill_screenshots
      token = generate_jwt
      app_id = ENV["ASC_APP_ID"]

      # Fetch all screenshot submissions from ASC
      uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions?limit=200")
      response = api_request(uri, token)
      return { error: "API request failed" } unless response && response["data"]

      # Build lookup: asc_feedback_id -> screenshot URLs
      screenshot_map = {}
      response["data"].each do |item|
        attrs = item["attributes"] || {}
        urls = Array(attrs["screenshots"]).filter_map { |s| s["url"] }
        screenshot_map[item["id"]] = urls if urls.any?
      end

      # Update existing feedbacks
      updated = 0
      TestflightFeedback.where(asc_feedback_id: screenshot_map.keys)
                        .where("screenshots = '[]' OR screenshots IS NULL")
                        .find_each do |feedback|
        urls = screenshot_map[feedback.asc_feedback_id]
        if urls&.any?
          feedback.update!(screenshots: urls)
          updated += 1
        end
      end

      { total_from_asc: screenshot_map.size, updated: updated }
    end

    # Debug: return raw ASC API responses for inspection
    def debug_raw_response
      token = generate_jwt
      app_id = ENV["ASC_APP_ID"]

      results = {}

      # Test 1: Screenshot submissions - no include params
      uri1 = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions?limit=3")
      results[:screenshot_plain] = raw_api_request(uri1, token)

      # Test 2: Crash submissions
      uri2 = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackCrashSubmissions?limit=3")
      results[:crash_plain] = raw_api_request(uri2, token)

      # Test 3: Screenshot submissions with include=betaScreenshots
      uri3 = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions?include=betaScreenshots&limit=3")
      results[:screenshot_with_beta_screenshots] = raw_api_request(uri3, token)

      # Test 4: Try individual screenshot submission to see relationships
      if results[:screenshot_plain][:status] == 200
        first_id = results[:screenshot_plain][:body].dig("data", 0, "id")
        if first_id
          uri4 = URI("#{ASC_API_BASE}/v1/betaFeedbackScreenshotSubmissions/#{first_id}?include=betaScreenshot")
          results[:single_with_include] = raw_api_request(uri4, token)
        end
      end

      results
    end

    # Raw API request that returns status code + body for debugging
    def raw_api_request(uri, token)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"

      response = http.request(request)
      body = begin
        JSON.parse(response.body)
      rescue StandardError
        response.body.truncate(1000)
      end

      { status: response.code.to_i, endpoint: uri.to_s, body: body }
    end

    private

    # Generate ES256 JWT for ASC API authentication
    def generate_jwt
      header = { kid: ENV["ASC_KEY_ID"] }
      now = Time.now.to_i

      payload = {
        iss: ENV["ASC_ISSUER_ID"],
        iat: now,
        exp: now + TOKEN_LIFETIME,
        aud: "appstoreconnect-v1"
      }

      private_key = OpenSSL::PKey::EC.new(formatted_private_key)
      JWT.encode(payload, private_key, "ES256", header)
    end

    # Format the private key from env (may be single-line with \n literals)
    def formatted_private_key
      key = ENV["ASC_PRIVATE_KEY"]
      return key if key.include?("-----BEGIN")

      # Handle base64-only format
      "-----BEGIN EC PRIVATE KEY-----\n#{key}\n-----END EC PRIVATE KEY-----"
    end

    # Fetch beta feedback from ASC API
    # Screenshots are embedded directly in attributes.screenshots[]
    def fetch_beta_feedback(token)
      app_id = ENV["ASC_APP_ID"]
      all_feedback = []

      # Screenshot feedback (screenshots are in attributes directly)
      screenshot_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions")
      response = api_request(screenshot_uri, token)
      if response && response["data"]
        Rails.logger.info("[AppStoreConnect] Screenshot feedback: #{response['data'].size} items")
        all_feedback.concat(response["data"].map { |d| normalize_feedback(d, "screenshot") })
      end

      # Crash feedback
      crash_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackCrashSubmissions")
      response = api_request(crash_uri, token)
      if response && response["data"]
        all_feedback.concat(response["data"].map { |d| normalize_feedback(d, "crash") })
      end

      all_feedback
    rescue StandardError => e
      Rails.logger.error("[AppStoreConnect] API request failed: #{e.message}")
      []
    end

    # Normalize feedback data to a consistent format for PollTestflightFeedbackJob
    def normalize_feedback(data, feedback_type)
      attrs = data["attributes"] || {}
      screenshot_urls = Array(attrs["screenshots"]).filter_map { |s| s["url"] }

      {
        "id" => data["id"],
        "type" => data["type"],
        "attributes" => {
          "comment" => attrs["comment"],
          "email" => attrs["email"],
          "deviceModel" => attrs["deviceModel"],
          "osVersion" => attrs["osVersion"],
          "locale" => attrs["locale"],
          "crashLog" => attrs["crashLog"],
          "feedbackType" => feedback_type,
          "timestamp" => attrs["createdDate"],
          "screenshots" => screenshot_urls
        }
      }
    end

    # Make authenticated GET request to ASC API
    def api_request(uri, token)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"

      response = http.request(request)

      if response.code.to_i == 200
        JSON.parse(response.body)
      else
        Rails.logger.warn("[AppStoreConnect] API returned #{response.code}: #{response.body.truncate(500)}")
        nil
      end
    end

    # Filter out feedbacks we've already processed
    def filter_new_feedbacks(feedbacks)
      return [] if feedbacks.empty?

      existing_ids = TestflightFeedback.where(
        asc_feedback_id: feedbacks.map { |f| f["id"] }
      ).pluck(:asc_feedback_id).to_set

      feedbacks.reject { |f| existing_ids.include?(f["id"]) }
    end
  end
end
