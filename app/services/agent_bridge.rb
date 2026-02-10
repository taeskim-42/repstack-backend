# frozen_string_literal: true

# AgentBridge: HTTP client for the Python Agent Service.
# Delegates chat processing to the Claude Agent SDK-based service.
# Falls back to legacy ChatService on failure.
class AgentBridge
  AGENT_SERVICE_URL = ENV["AGENT_SERVICE_URL"]
  AGENT_API_TOKEN = ENV["AGENT_API_TOKEN"]
  TIMEOUT = 60 # seconds

  class << self
    def process(user:, message:, routine_id: nil, session_id: nil)
      return legacy_fallback(user, message, routine_id, session_id) unless available?

      response = post_chat(
        user_id: user.id,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      )

      parse_response(response)
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      Rails.logger.error("[AgentBridge] Timeout: #{e.message}")
      legacy_fallback(user, message, routine_id, session_id)
    rescue StandardError => e
      Rails.logger.error("[AgentBridge] Error: #{e.class} - #{e.message}")
      legacy_fallback(user, message, routine_id, session_id)
    end

    def available?
      AGENT_SERVICE_URL.present? && AGENT_API_TOKEN.present?
    end

    def healthy?
      return false unless available?

      uri = URI("#{AGENT_SERVICE_URL}/health")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def session_status(user_id)
      return nil unless available?

      uri = URI("#{AGENT_SERVICE_URL}/sessions/#{user_id}/status")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{AGENT_API_TOKEN}"

      response = make_request(uri, request)
      JSON.parse(response.body, symbolize_names: true) if response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      nil
    end

    def reset_session(user_id)
      return false unless available?

      uri = URI("#{AGENT_SERVICE_URL}/sessions/#{user_id}/reset")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{AGENT_API_TOKEN}"
      request["Content-Type"] = "application/json"

      response = make_request(uri, request)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    private

    def post_chat(user_id:, message:, routine_id:, session_id:)
      uri = URI("#{AGENT_SERVICE_URL}/chat")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{AGENT_API_TOKEN}"
      request["Content-Type"] = "application/json"
      request.body = {
        user_id: user_id,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      }.compact.to_json

      make_request(uri, request)
    end

    def make_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = TIMEOUT
      http.request(request)
    end

    def parse_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[AgentBridge] HTTP #{response.code}: #{response.body}")
        return nil
      end

      data = JSON.parse(response.body, symbolize_names: true)

      {
        success: data[:success] != false,
        message: data[:message],
        intent: data[:intent],
        data: data[:data] || {},
        error: data[:error],
        agent_session_id: data[:session_id],
        cost_usd: data[:cost_usd],
        tokens_used: data[:tokens_used]
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[AgentBridge] JSON parse error: #{e.message}")
      nil
    end

    def legacy_fallback(user, message, routine_id, session_id)
      Rails.logger.info("[AgentBridge] Falling back to legacy ChatService")
      ChatService.process(
        user: user,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      )
    end
  end
end
