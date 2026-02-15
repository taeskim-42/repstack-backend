# frozen_string_literal: true

# Async job to analyze a TestFlight feedback with AI
# Triggers GitHub issue creation on success
class TestflightFeedbackAnalysisJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  def perform(feedback_id)
    feedback = TestflightFeedback.find_by(id: feedback_id)
    return unless feedback
    return unless feedback.status == "received"

    result = TestflightFeedbackAnalyzer.analyze(feedback)

    if result[:success]
      Rails.logger.info("[FeedbackAnalysis] Feedback ##{feedback_id} analyzed: #{result[:result]['bug_category']} / #{result[:result]['severity']}")

      # Trigger GitHub issue creation
      TestflightGithubIssueJob.perform_async(feedback_id)

      # Broadcast to ActionCable for team system real-time consumption
      ActionCable.server.broadcast("testflight_feedback", {
        id: feedback.id,
        severity: feedback.severity,
        bug_category: feedback.bug_category,
        affected_repo: feedback.affected_repo,
        summary: feedback.ai_analysis_json&.dig("summary"),
        feedback_text: feedback.feedback_text&.truncate(200),
        app_version: feedback.app_version,
        classified_at: Time.current.iso8601
      })

      # Send notification
      NotificationService.notify(
        event: :feedback_analyzed,
        feedback: feedback,
        details: result[:result]
      )
    else
      Rails.logger.error("[FeedbackAnalysis] Failed for ##{feedback_id}: #{result[:error]}")
    end
  end
end
