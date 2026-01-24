# frozen_string_literal: true

class FitnessTestSubmission < ApplicationRecord
  belongs_to :user

  # Status constants
  STATUSES = %w[pending processing completed failed].freeze

  # Validations
  validates :job_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  # Status helper methods
  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  # Mark as processing
  def start_processing!
    update!(status: "processing", started_at: Time.current)
  end

  # Mark as completed with results
  def complete_with_results!(result)
    update!(
      status: "completed",
      completed_at: Time.current,
      fitness_score: result[:fitness_score],
      assigned_level: result[:assigned_level],
      assigned_tier: result[:assigned_tier],
      evaluation_result: result
    )
  end

  # Mark as failed with error
  def fail_with_error!(message)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: message
    )
  end

  # Add a video to the submission
  # @param exercise_type [String] e.g., "pushup", "bench_press", "squat"
  # @param video_key [String] S3 key
  def add_video(exercise_type:, video_key:)
    self.videos = videos.reject { |v| v["exercise_type"] == exercise_type }
    self.videos << { "exercise_type" => exercise_type, "video_key" => video_key }
    save!
  end

  # Store analysis result for an exercise
  def store_analysis!(exercise_type, analysis)
    self.analyses = analyses.merge(exercise_type.to_s => analysis)
    save!
  end

  # Get video key for a specific exercise
  def video_key_for(exercise_type)
    videos.find { |v| v["exercise_type"] == exercise_type.to_s }&.dig("video_key")
  end

  # Get analysis for a specific exercise
  def analysis_for(exercise_type)
    analyses[exercise_type.to_s]
  end

  # Get all video keys
  def all_video_keys
    videos.map { |v| v["video_key"] }
  end

  # Get all exercise types
  def exercise_types
    videos.map { |v| v["exercise_type"] }
  end

  # Check if all expected videos are uploaded
  def videos_complete?(expected_types)
    expected_types.all? { |type| video_key_for(type).present? }
  end
end
