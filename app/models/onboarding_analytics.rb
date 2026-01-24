# frozen_string_literal: true

class OnboardingAnalytics < ApplicationRecord
  belongs_to :user

  validates :session_id, presence: true, uniqueness: true

  scope :completed, -> { where(completed: true) }
  scope :abandoned, -> { where(completed: false) }
  scope :by_version, ->(version) { where(prompt_version: version) }
  scope :recent, ->(days = 7) { where("created_at > ?", days.days.ago) }

  # 분석 메서드들
  class << self
    def completion_rate(days: 7)
      records = recent(days)
      total = records.count
      return 0 if total.zero?

      (records.completed.count.to_f / total * 100).round(1)
    end

    def average_turns(days: 7)
      recent(days).completed.average(:turn_count)&.round(1) || 0
    end

    def by_prompt_version_stats(days: 30)
      recent(days)
        .group(:prompt_version)
        .select(
          "prompt_version",
          "COUNT(*) as total",
          "SUM(CASE WHEN completed THEN 1 ELSE 0 END) as completed_count",
          "ROUND(AVG(turn_count), 1) as avg_turns"
        )
    end

    def abandonment_by_turn(days: 7)
      recent(days)
        .abandoned
        .group(:turn_count)
        .count
        .sort_by { |k, _| k }
    end

    def collected_info_stats(days: 7)
      records = recent(days).completed
      total = records.count
      return {} if total.zero?

      info_counts = Hash.new(0)
      records.pluck(:collected_info).each do |info|
        info&.keys&.each { |key| info_counts[key] += 1 }
      end

      info_counts.transform_values { |count| (count.to_f / total * 100).round(1) }
    end

    def weekly_report
      {
        period: "#{7.days.ago.to_date} ~ #{Date.current}",
        total_sessions: recent(7).count,
        completion_rate: completion_rate,
        average_turns: average_turns,
        abandonment_points: abandonment_by_turn,
        info_collection_rate: collected_info_stats
      }
    end
  end
end
