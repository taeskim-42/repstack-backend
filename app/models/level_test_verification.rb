# frozen_string_literal: true

class LevelTestVerification < ApplicationRecord
  belongs_to :user

  # Status constants
  STATUSES = %w[pending in_progress passed failed].freeze

  # Exercise types
  EXERCISE_TYPES = %w[bench squat deadlift].freeze

  # Validations
  validates :test_id, presence: true, uniqueness: true
  validates :current_level, presence: true, numericality: { in: 1..8 }
  validates :target_level, presence: true, numericality: { in: 2..8 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :passed, -> { where(status: 'passed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_defaults, on: :create

  # Check if all exercises passed
  def all_exercises_passed?
    return false if exercises.blank?

    exercises.all? { |ex| ex['passed'] == true }
  end

  # Get exercise result by type
  def exercise_result(type)
    exercises.find { |ex| ex['exercise_type'] == type.to_s }
  end

  # Mark as passed and update user level
  def complete_as_passed!
    transaction do
      update!(
        status: 'passed',
        passed: true,
        new_level: target_level,
        completed_at: Time.current
      )

      # Update user profile
      user.user_profile&.update!(
        numeric_level: target_level,
        last_level_test_at: Time.current
      )
    end
  end

  # Mark as failed
  def complete_as_failed!(feedback: nil)
    update!(
      status: 'failed',
      passed: false,
      new_level: current_level,
      ai_feedback: feedback,
      completed_at: Time.current
    )
  end

  # Add exercise verification result
  def add_exercise_result(exercise_type:, weight_kg:, passed:, pose_score: nil, video_url: nil, form_issues: [])
    exercise_data = {
      'exercise_type' => exercise_type.to_s,
      'weight_kg' => weight_kg,
      'passed' => passed,
      'pose_score' => pose_score,
      'video_url' => video_url,
      'form_issues' => form_issues,
      'verified_at' => Time.current.iso8601
    }

    self.exercises = (exercises || []).reject { |ex| ex['exercise_type'] == exercise_type.to_s }
    self.exercises << exercise_data
    save!
  end

  private

  def set_defaults
    self.status ||= 'pending'
    self.exercises ||= []
    self.started_at ||= Time.current
  end
end
