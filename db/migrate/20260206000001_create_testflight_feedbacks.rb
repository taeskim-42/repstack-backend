# frozen_string_literal: true

class CreateTestflightFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :testflight_feedbacks do |t|
      # ASC API identifiers
      t.string :asc_feedback_id, null: false
      t.text :feedback_text

      # Build info
      t.string :app_version
      t.string :build_number

      # Device info
      t.string :device_model
      t.string :os_version

      # Crash data
      t.text :crash_log
      t.jsonb :screenshots, default: []

      # AI analysis results
      t.string :bug_category  # crash, ui_bug, performance, feature_request, other
      t.string :severity      # critical, high, medium, low
      t.string :affected_repo # backend, frontend, both, unknown
      t.text :ai_analysis
      t.jsonb :ai_analysis_json, default: {}

      # Pipeline tracking
      t.string :status, null: false, default: "received"
      t.string :github_issue_url
      t.string :github_pr_url
      t.jsonb :pipeline_log, default: []

      t.timestamps
    end

    add_index :testflight_feedbacks, :asc_feedback_id, unique: true
    add_index :testflight_feedbacks, :status
    add_index :testflight_feedbacks, :severity
    add_index :testflight_feedbacks, :bug_category
  end
end
