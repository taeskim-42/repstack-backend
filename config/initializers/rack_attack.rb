# frozen_string_literal: true

# Rack::Attack configuration for rate limiting and request throttling
# See: https://github.com/rack/rack-attack

class Rack::Attack
  # Use Redis for distributed rate limiting if available
  if ENV["REDIS_URL"].present?
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV["REDIS_URL"], namespace: "rack_attack"
    )
  else
    Rack::Attack.cache.store = Rails.cache
  end

  ### Throttling rules ###

  # General API rate limit: 100 requests per minute per IP
  throttle("req/ip", limit: 100, period: 1.minute) do |req|
    req.ip unless req.path.start_with?("/health")
  end

  # Stricter limit for authentication endpoints: 5 requests per 20 seconds
  throttle("auth/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/graphql" && req.post?
      # Check if it's a sign-in or sign-up mutation
      body = req.body.read
      req.body.rewind
      if body.include?("signIn") || body.include?("signUp")
        req.ip
      end
    end
  end

  # AI routine generation limit: 10 requests per minute per user
  throttle("ai/user", limit: 10, period: 1.minute) do |req|
    if req.path == "/graphql" && req.post?
      body = req.body.read
      req.body.rewind
      if body.include?("generateRoutine")
        # Try to extract user from token
        extract_user_id_from_request(req) || req.ip
      end
    end
  end

  # Block IPs with repeated auth failures (tracked at app layer)
  blocklist("fail2ban/auth") do |req|
    if req.path == "/graphql" && req.post?
      fail_count = Rails.cache.read("auth_failure:#{req.ip}").to_i
      fail_count >= 10
    end
  end

  ### Safelist rules ###

  # Always allow localhost (development)
  safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  # Allow health check endpoints
  safelist("allow-health-checks") do |req|
    req.path.start_with?("/health")
  end

  # Allow internal API (Agent Service → Rails, Bearer token auth)
  safelist("allow-internal-api") do |req|
    req.path.start_with?("/internal/")
  end

  ### Blocklist rules ###

  # Block requests from known bad IPs (can be populated from external source)
  blocklist("block-bad-ips") do |req|
    blocked_ips.include?(req.ip)
  end

  ### Custom responses ###

  # Customize throttled response
  self.throttled_responder = lambda do |req|
    now = Time.current
    retry_after = (req.env["rack.attack.match_data"] || {})[:period]

    headers = {
      "Content-Type" => "application/json",
      "Retry-After" => retry_after.to_s
    }

    body = {
      error: true,
      message: "요청이 너무 많습니다. #{retry_after}초 후에 다시 시도해주세요.",
      retry_after: retry_after
    }.to_json

    [ 429, headers, [ body ] ]
  end

  # Customize blocked response
  self.blocklisted_responder = lambda do |req|
    headers = { "Content-Type" => "application/json" }
    body = {
      error: true,
      message: "접근이 차단되었습니다."
    }.to_json

    [ 403, headers, [ body ] ]
  end

  ### Helper methods ###

  def self.blocked_ips
    # Load blocked IPs from cache or config
    Rails.cache.fetch("rack_attack:blocked_ips", expires_in: 5.minutes) do
      # Could load from database, file, or external service
      []
    end
  end

  def self.extract_user_id_from_request(req)
    auth_header = req.env["HTTP_AUTHORIZATION"]
    return nil unless auth_header&.start_with?("Bearer ")

    token = auth_header.split(" ").last
    decoded = JsonWebToken.decode(token)
    decoded[:user_id]
  rescue StandardError
    nil
  end
end

# Log throttled requests
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |name, start, finish, request_id, payload|
  req = payload[:request]
  Rails.logger.warn({
    event: "rate_limit.throttled",
    ip: req.ip,
    path: req.path,
    throttle_name: req.env["rack.attack.matched"],
    retry_after: req.env.dig("rack.attack.match_data", :period)
  }.to_json)
end

# Log blocked requests
ActiveSupport::Notifications.subscribe("blocklist.rack_attack") do |name, start, finish, request_id, payload|
  req = payload[:request]
  Rails.logger.warn({
    event: "rate_limit.blocked",
    ip: req.ip,
    path: req.path,
    blocklist_name: req.env["rack.attack.matched"]
  }.to_json)
end
