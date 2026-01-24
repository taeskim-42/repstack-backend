# frozen_string_literal: true

class CreateOnboardingAnalytics < ActiveRecord::Migration[8.0]
  def change
    create_table :onboarding_analytics do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_id, null: false
      t.integer :turn_count, default: 0
      t.boolean :completed, default: false
      t.string :completion_reason # "user_ready", "max_turns", "error", "abandoned"
      t.jsonb :collected_info, default: {} # experience, frequency, goals 등
      t.jsonb :conversation_log, default: [] # 전체 대화 로그
      t.string :prompt_version # 프롬프트 버전 추적
      t.integer :time_to_complete_seconds
      t.timestamps
    end

    add_index :onboarding_analytics, :session_id, unique: true
    add_index :onboarding_analytics, :completed
    add_index :onboarding_analytics, :prompt_version
    add_index :onboarding_analytics, :created_at
  end
end
