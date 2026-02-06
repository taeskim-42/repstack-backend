# frozen_string_literal: true

class TestflightFeedback < ApplicationRecord
  # Status flow: received → analyzing → issue_created → fix_in_progress → fix_merged → deployed
  STATUSES = %w[received analyzing issue_created fix_in_progress fix_merged deployed failed].freeze
  BUG_CATEGORIES = %w[crash ui_bug performance feature_request other].freeze
  SEVERITIES = %w[critical high medium low].freeze
  AFFECTED_REPOS = %w[backend frontend both unknown].freeze

  validates :asc_feedback_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :bug_category, inclusion: { in: BUG_CATEGORIES }, allow_nil: true
  validates :severity, inclusion: { in: SEVERITIES }, allow_nil: true
  validates :affected_repo, inclusion: { in: AFFECTED_REPOS }, allow_nil: true

  scope :pending_analysis, -> { where(status: "received") }
  scope :by_severity, ->(sev) { where(severity: sev) }
  scope :actionable, -> { where(bug_category: %w[crash ui_bug performance]) }

  # Append a timestamped entry to pipeline_log
  def log_pipeline_event(event, details = {})
    entry = { event: event, at: Time.current.iso8601, **details }
    self.pipeline_log = (pipeline_log || []) + [entry]
    save!
  end

  # All feedback gets auto-fix label for full automation
  def auto_fixable?
    true
  end

  # Target GitHub repo based on affected_repo
  def target_repos
    case affected_repo
    when "backend"  then ["taeskim-42/repstack-backend"]
    when "frontend" then ["taeskim-42/repstack-frontend"]
    when "both"     then ["taeskim-42/repstack-backend", "taeskim-42/repstack-frontend"]
    else ["taeskim-42/repstack-backend"]
    end
  end
end
