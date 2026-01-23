# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password validations: false

  # Associations
  has_one :user_profile, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy
  has_many :workout_routines, dependent: :destroy
  has_many :workout_sets, through: :workout_sessions
  has_many :condition_logs, dependent: :destroy
  has_many :workout_records, dependent: :destroy
  has_many :workout_feedbacks, dependent: :destroy
  has_many :level_test_verifications, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :password, length: { minimum: 6 }, if: :password_required?
  validates :apple_user_id, uniqueness: true, allow_nil: true

  # Callbacks
  before_save :downcase_email

  # Scopes
  scope :with_profiles, -> { includes(:user_profile) }

  # Class methods
  def self.find_or_create_from_apple(apple_user_id:, email:, name: nil)
    user = find_by(apple_user_id: apple_user_id)
    return user if user

    # Check if user exists with the same email
    user = find_by(email: email.downcase)
    if user
      user.update!(apple_user_id: apple_user_id)
      return user
    end

    # Create new user
    create!(
      apple_user_id: apple_user_id,
      email: email,
      name: name || email.split("@").first
    )
  end

  # Instance methods
  def apple_user?
    apple_user_id.present?
  end

  def current_workout_session
    workout_sessions.where(end_time: nil).first
  end

  def has_active_workout?
    current_workout_session.present?
  end

  def total_workout_sessions
    workout_sessions.where.not(end_time: nil).count
  end

  def current_routine
    workout_routines.where(
      level: user_profile&.current_level,
      week_number: user_profile&.week_number,
      day_number: user_profile&.day_number,
      is_completed: false
    ).first
  end

  private

  def downcase_email
    self.email = email.downcase
  end

  def password_required?
    return false if apple_user?
    new_record? || password.present?
  end
end
