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
