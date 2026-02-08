# frozen_string_literal: true

# Classifies TestFlight feedback using Claude AI
# Only categorizes — root cause analysis is done by Opus in /poll-feedback
class TestflightFeedbackAnalyzer
  SYSTEM_PROMPT = <<~PROMPT
    You are a bug classifier for RepStack, a fitness app.
    Classify TestFlight user feedback into exactly 4 fields.
    Do NOT guess root causes, affected files, or fixes.
    Respond ONLY with valid JSON:

    {
      "bug_category": "crash|ui_bug|performance|feature_request|other",
      "severity": "critical|high|medium|low",
      "affected_repo": "backend|frontend|both|unknown",
      "summary": "한국어 한 줄 요약"
    }

    Classification rules:
    - crash + data loss = critical
    - crash without data loss = high
    - UI broken / wrong data displayed = medium
    - cosmetic / minor = low
    - feature_request = always low severity

    Repo detection:
    - Swift symbols, UI layout, animation = frontend
    - API errors, 500 status, GraphQL = backend
    - Both indicators present = both
    - If unclear = unknown (Opus will investigate later)
  PROMPT

  class << self
    # Analyze a single feedback record
    # @param feedback [TestflightFeedback]
    # @return [Hash] Analysis result
    def analyze(feedback)
      feedback.update!(status: "analyzing")
      feedback.log_pipeline_event("analysis_started")

      prompt = build_prompt(feedback)
      response = AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :testflight_analysis,
        system: SYSTEM_PROMPT
      )

      unless response[:success]
        feedback.log_pipeline_event("analysis_failed", error: response[:error])
        return { success: false, error: response[:error] }
      end

      result = parse_analysis(response[:content])

      # Apply rule-based overrides
      result = apply_heuristics(result, feedback)

      feedback.update!(
        bug_category: result["bug_category"],
        severity: result["severity"],
        affected_repo: result["affected_repo"],
        ai_analysis: response[:content],
        ai_analysis_json: result
      )

      feedback.log_pipeline_event("analysis_completed", result: result)
      { success: true, result: result }
    rescue StandardError => e
      Rails.logger.error("[FeedbackAnalyzer] Error: #{e.message}")
      feedback.update!(status: "failed") if feedback.persisted?
      feedback.log_pipeline_event("analysis_error", error: e.message)
      { success: false, error: e.message }
    end

    private

    def build_prompt(feedback)
      parts = ["TestFlight Feedback Analysis Request:\n"]
      parts << "Feedback text: #{feedback.feedback_text}" if feedback.feedback_text.present?
      parts << "App version: #{feedback.app_version}" if feedback.app_version.present?
      parts << "Build: #{feedback.build_number}" if feedback.build_number.present?
      parts << "Device: #{feedback.device_model}" if feedback.device_model.present?
      parts << "OS: #{feedback.os_version}" if feedback.os_version.present?

      if feedback.crash_log.present?
        parts << "\nCrash Log:\n```\n#{feedback.crash_log.truncate(2000)}\n```"
      end

      parts.join("\n")
    end

    def parse_analysis(content)
      # Extract JSON from response (may be wrapped in markdown code block)
      json_str = content.match(/\{.*\}/m)&.to_s
      return default_analysis unless json_str

      JSON.parse(json_str)
    rescue JSON::ParserError
      default_analysis
    end

    def default_analysis
      {
        "bug_category" => "other",
        "severity" => "low",
        "affected_repo" => "unknown",
        "summary" => "분류 실패 — 수동 확인 필요"
      }
    end

    # Rule-based heuristics to complement AI analysis
    def apply_heuristics(result, feedback)
      text = "#{feedback.feedback_text} #{feedback.crash_log}".downcase

      # Swift-specific symbols → frontend
      if text.match?(/swift|uikit|swiftui|viewcontroller|nsexception|sigabrt|exc_bad_access/)
        result["affected_repo"] = "frontend" if result["affected_repo"] == "unknown"
      end

      # API/backend indicators → backend
      if text.match?(/graphql|500\s*(error|status)|api\s*error|activerecord|postgresql|sidekiq/)
        result["affected_repo"] = "backend" if result["affected_repo"] == "unknown"
      end

      # Crash log with both indicators → both
      if text.match?(/swift|uikit/) && text.match?(/api|graphql|500/)
        result["affected_repo"] = "both"
      end

      result
    end
  end
end
