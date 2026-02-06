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

      # Screenshot feedback (user-submitted via TestFlight "Send Feedback")
      screenshot_uri = URI("#{ASC_API_BASE}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions")
      response = api_request(screenshot_uri, token)
      if response && response["data"]
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
          "timestamp" => attrs["timestamp"] || attrs["createdDate"]
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
