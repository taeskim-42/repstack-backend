# frozen_string_literal: true

# Sends notifications for TestFlight feedback pipeline events
# Supports Slack/Discord webhooks
class NotificationService
  EVENTS = {
    feedback_received: { emoji: "📥", title: "New TestFlight Feedback" },
    feedback_analyzed: { emoji: "🔍", title: "Feedback Analyzed" },
    issue_created: { emoji: "📝", title: "GitHub Issue Created" },
    pr_created: { emoji: "🔧", title: "Fix PR Created" },
    fix_merged: { emoji: "✅", title: "Fix Merged" },
    deployed: { emoji: "🚀", title: "Fix Deployed" }
  }.freeze

  class << self
    # Send a pipeline event notification
    # @param event [Symbol] Event type
    # @param feedback [TestflightFeedback] The feedback record
    # @param details [Hash] Additional details
    def notify(event:, feedback:, details: {})
      return unless webhook_configured?

      event_config = EVENTS[event]
      return unless event_config

      message = build_message(event, event_config, feedback, details)
      send_webhook(message)
    rescue StandardError => e
      Rails.logger.error("[Notification] Failed to send: #{e.message}")
    end

    def webhook_configured?
      ENV["NOTIFICATION_WEBHOOK_URL"].present?
    end

    private

    def build_message(event, config, feedback, details)
      text = "#{config[:emoji]} **#{config[:title]}**\n"

      case event
      when :feedback_received
        text += "Feedback: #{feedback.feedback_text.to_s.truncate(200)}\n"
        text += "Version: #{feedback.app_version} (#{feedback.build_number})"
      when :feedback_analyzed
        text += "Category: #{feedback.bug_category} | Severity: #{feedback.severity}\n"
        text += "Repo: #{feedback.affected_repo}\n"
        text += "Auto-fix: #{feedback.auto_fixable? ? 'Yes' : 'No (manual review required)'}"
      when :issue_created
        text += "Issue: #{details[:url]}\n"
        text += "Repo: #{details[:repo]}"
      when :pr_created
        text += "PR: #{details[:url]}"
      when :fix_merged
        text += "Merged! Deployment in progress..."
      when :deployed
        text += "Fix deployed successfully!"
      end

      # Webhook payload (compatible with both Slack and Discord)
      { content: text }
    end

    def send_webhook(message)
      uri = URI(ENV["NOTIFICATION_WEBHOOK_URL"])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request.body = message.to_json

      response = http.request(request)

      unless response.code.to_i.between?(200, 299)
        Rails.logger.warn("[Notification] Webhook returned #{response.code}")
      end
    end
  end
end
