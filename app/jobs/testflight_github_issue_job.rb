# frozen_string_literal: true

# Creates GitHub issues from analyzed TestFlight feedback
# Applies labels based on severity and category
# Auto-fix label only for medium/low severity
class TestflightGithubIssueJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  GITHUB_API_BASE = "https://api.github.com"

  def perform(feedback_id)
    feedback = TestflightFeedback.find_by(id: feedback_id)
    return unless feedback
    return unless feedback.status == "analyzing"
    return unless ENV["GITHUB_PAT"].present?

    feedback.target_repos.each do |repo|
      issue_url = create_issue(feedback, repo)
      next unless issue_url

      feedback.update!(
        status: "issue_created",
        github_issue_url: issue_url
      )
      feedback.log_pipeline_event("issue_created", repo: repo, url: issue_url)

      NotificationService.notify(
        event: :issue_created,
        feedback: feedback,
        details: { repo: repo, url: issue_url }
      )
    end
  rescue StandardError => e
    Rails.logger.error("[GithubIssue] Error creating issue for feedback ##{feedback_id}: #{e.message}")
    feedback&.log_pipeline_event("issue_creation_failed", error: e.message)
  end

  private

  def create_issue(feedback, repo)
    uri = URI("#{GITHUB_API_BASE}/repos/#{repo}/issues")
    analysis = feedback.ai_analysis_json || {}

    body = build_issue_body(feedback, analysis)
    labels = build_labels(feedback)

    payload = {
      title: "[TestFlight] #{analysis['summary'] || 'Bug Report'} (#{feedback.app_version})",
      body: body,
      labels: labels
    }

    response = github_post(uri, payload)
    return nil unless response

    data = JSON.parse(response.body)

    if response.code.to_i == 201
      Rails.logger.info("[GithubIssue] Created issue ##{data['number']} in #{repo}")
      data["html_url"]
    else
      Rails.logger.error("[GithubIssue] Failed to create issue: #{response.code} - #{response.body.truncate(500)}")
      nil
    end
  end

  def build_issue_body(feedback, analysis)
    body = <<~BODY
      ## TestFlight Feedback Report

      **Category:** #{feedback.bug_category}
      **Severity:** #{feedback.severity}
      **Affected Repo:** #{feedback.affected_repo}
      **App Version:** #{feedback.app_version} (#{feedback.build_number})
      **Device:** #{feedback.device_model} / #{feedback.os_version}

      ## User Feedback

      #{feedback.feedback_text || 'No feedback text provided'}

      ## AI Analysis

      **Root Cause Hypothesis:** #{analysis['root_cause_hypothesis']}

      **Suggested Fix:** #{analysis['suggested_fix']}

      **Affected Files (hint):**
      #{(analysis['affected_files_hint'] || []).map { |f| "- `#{f}`" }.join("\n")}
    BODY

    if feedback.screenshots.present?
      body += "\n## Screenshots\n\n"
      feedback.screenshots.each_with_index do |url, i|
        body += "![Screenshot #{i + 1}](#{url})\n\n"
      end
    end

    if feedback.crash_log.present?
      body += <<~CRASH

        ## Crash Log

        ```
        #{feedback.crash_log.truncate(3000)}
        ```
      CRASH
    end

    body += "\n\n---\n_Auto-generated from TestFlight feedback pipeline_"
    body
  end

  def build_labels(feedback)
    labels = ["testflight-feedback"]
    labels << "severity:#{feedback.severity}" if feedback.severity
    labels << "bug:#{feedback.bug_category}" if feedback.bug_category
    labels << "auto-fix" if feedback.auto_fixable?
    labels
  end

  def github_post(uri, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{ENV['GITHUB_PAT']}"
    request["Accept"] = "application/vnd.github+json"
    request["Content-Type"] = "application/json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request.body = payload.to_json

    http.request(request)
  rescue StandardError => e
    Rails.logger.error("[GithubIssue] HTTP error: #{e.message}")
    nil
  end
end
