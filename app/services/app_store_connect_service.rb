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

    # Debug: return raw ASC API responses for inspection
    def debug_raw_response
      token = generate_jwt
      app_id = ENV["ASC_APP_ID"]

      results = {}

      # Test 1: Screenshot submissions endpoint
      screenshot_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions?include=screenshots&fields[betaScreenshots]=imageAsset&limit=3")
      raw1 = raw_api_request(screenshot_uri, token)
      results[:screenshot_submissions] = raw1

      # Test 2: Try betaAppReviewSubmissions (older API)
      review_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaAppReviewSubmissions?limit=3")
      raw2 = raw_api_request(review_uri, token)
      results[:beta_review_submissions] = raw2

      # Test 3: Try betaTesterUsages or builds
      builds_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/builds?limit=1&sort=-uploadedDate")
      raw3 = raw_api_request(builds_uri, token)
      results[:latest_build] = raw3

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

    # Fetch beta feedback from ASC Feedback API (WWDC 2025)
    # Uses /v1/apps/{appId}/betaFeedbackScreenshotSubmissions
    # and /v1/apps/{appId}/betaFeedbackCrashSubmissions
    def fetch_beta_feedback(token)
      app_id = ENV["ASC_APP_ID"]
      all_feedback = []

      # Screenshot feedback - include related screenshots
      screenshot_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions?include=screenshots&fields[betaScreenshots]=imageAsset")
      response = api_request(screenshot_uri, token)
      if response && response["data"]
        included = response["included"] || []
        Rails.logger.info("[AppStoreConnect] Screenshot feedback: #{response['data'].size} items, #{included.size} included resources")
        Rails.logger.info("[AppStoreConnect] Sample data keys: #{response['data'].first&.keys}") if response["data"].any?
        Rails.logger.info("[AppStoreConnect] Sample relationships: #{response['data'].first&.dig('relationships')&.keys}") if response["data"].any?
        Rails.logger.info("[AppStoreConnect] Sample included: #{included.first&.slice('id', 'type', 'attributes')}") if included.any?
        all_feedback.concat(response["data"].map { |d| normalize_feedback(d, "screenshot", included) })
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
    def normalize_feedback(data, feedback_type, included = [])
      attrs = data["attributes"] || {}
      {
        "id" => data["id"],
        "type" => data["type"],
        "attributes" => {
          "comment" => attrs["comment"] || attrs["feedback"] || attrs["description"],
          "appVersionString" => attrs["appVersionString"] || attrs["appVersion"],
          "buildNumber" => attrs["buildNumber"],
          "deviceModel" => attrs["deviceModel"],
          "osVersion" => attrs["osVersion"],
          "crashLog" => attrs["crashLog"],
          "feedbackType" => feedback_type,
          "timestamp" => attrs["timestamp"] || attrs["createdDate"],
          "screenshots" => extract_screenshot_urls(data, included)
        }
      }
    end

    # Extract screenshot image URLs from ASC included resources
    def extract_screenshot_urls(data, included)
      return [] if included.empty?

      # Get screenshot IDs from relationships (try both singular and plural)
      screenshot_refs = data.dig("relationships", "screenshots", "data") ||
                        Array(data.dig("relationships", "screenshot", "data"))
      Rails.logger.info("[AppStoreConnect] Relationships for #{data['id']}: #{data.dig('relationships')&.keys&.join(', ')}")
      Rails.logger.info("[AppStoreConnect] Screenshot refs: #{screenshot_refs.inspect}")
      screenshot_ids = screenshot_refs.map { |s| s["id"] }
      return [] if screenshot_ids.empty?

      # Match included resources and extract image URLs
      included.select { |r| screenshot_ids.include?(r["id"]) }.filter_map do |resource|
        attrs = resource["attributes"] || {}
        # ASC imageAsset has templateUrl with {w}, {h}, {f} placeholders
        image_asset = attrs["imageAsset"] || {}
        template_url = image_asset["templateUrl"]

        if template_url
          w = image_asset["width"] || 1170
          h = image_asset["height"] || 2532
          template_url.gsub("{w}", w.to_s).gsub("{h}", h.to_s).gsub("{f}", "png")
        else
          # Fallback: direct URL fields
          attrs["imageUrl"] || attrs["url"]
        end
      end
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
