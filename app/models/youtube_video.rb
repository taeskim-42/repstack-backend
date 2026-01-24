# frozen_string_literal: true

class YoutubeVideo < ApplicationRecord
  belongs_to :youtube_channel
  has_many :fitness_knowledge_chunks, dependent: :destroy

  # Analysis statuses
  STATUSES = %w[pending analyzing completed failed].freeze

  # Validations
  validates :video_id, presence: true, uniqueness: true
  validates :title, presence: true
  validates :analysis_status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :pending, -> { where(analysis_status: "pending") }
  scope :analyzing, -> { where(analysis_status: "analyzing") }
  scope :completed, -> { where(analysis_status: "completed") }
  scope :failed, -> { where(analysis_status: "failed") }
  scope :needs_analysis, -> { pending }
  scope :published_after, ->(date) { where("published_at > ?", date) }
  scope :by_channel, ->(channel_id) { where(youtube_channel_id: channel_id) }

  # Status transition methods
  def start_analysis!
    update!(analysis_status: "analyzing")
  end

  def complete_analysis!(analysis_result)
    update!(
      analysis_status: "completed",
      analyzed_at: Time.current,
      raw_analysis: analysis_result,
      category: analysis_result[:category],
      difficulty_level: analysis_result[:difficulty_level],
      language: analysis_result[:language]
    )
  end

  def fail_analysis!(error_message)
    update!(
      analysis_status: "failed",
      analysis_error: error_message
    )
  end

  def retry_analysis!
    update!(
      analysis_status: "pending",
      analysis_error: nil
    )
  end

  # Helper methods
  def youtube_url
    "https://www.youtube.com/watch?v=#{video_id}"
  end

  def analyzed?
    analysis_status == "completed"
  end

  def duration_formatted
    return nil unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    format("%d:%02d", minutes, seconds)
  end
end
