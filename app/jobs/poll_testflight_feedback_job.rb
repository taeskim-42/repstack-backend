# frozen_string_literal: true

# Polls App Store Connect API for new TestFlight feedback
# Runs every 5 minutes via Sidekiq Cron
class PollTestflightFeedbackJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 1

  def perform
    unless AppStoreConnectService.configured?
      Rails.logger.info("[PollFeedback] App Store Connect not configured, skipping")
      return
    end

    new_feedbacks = AppStoreConnectService.fetch_new_feedback
    Rails.logger.info("[PollFeedback] Found #{new_feedbacks.size} new feedback(s)")

    new_feedbacks.each do |feedback_data|
      feedback = create_feedback_record(feedback_data)
      next unless feedback

      # Trigger async AI analysis
      TestflightFeedbackAnalysisJob.perform_async(feedback.id)

      NotificationService.notify(
        event: :feedback_received,
        feedback: feedback
      )
    end
  rescue StandardError => e
    Rails.logger.error("[PollFeedback] Error: #{e.message}")
  end

  private

  def create_feedback_record(data)
    attrs = data.dig("attributes") || {}

    TestflightFeedback.create!(
      asc_feedback_id: data["id"],
      feedback_text: attrs["comment"] || attrs["feedback"],
      app_version: attrs["appVersionString"],
      build_number: attrs["buildNumber"],
      device_model: attrs["deviceModel"],
      os_version: attrs["osVersion"],
      crash_log: attrs["crashLog"],
      screenshots: attrs["screenshots"] || [],
      status: "received",
      pipeline_log: [{ event: "received", at: Time.current.iso8601 }]
    )
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[PollFeedback] Duplicate feedback: #{data['id']}")
    nil
  rescue StandardError => e
    Rails.logger.error("[PollFeedback] Error creating feedback: #{e.message}")
    nil
  end
end
