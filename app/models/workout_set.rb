class WorkoutSet < ApplicationRecord
  belongs_to :workout_session

  # Validations
  validates :exercise_name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :weight, numericality: { greater_than: 0 }, allow_nil: true
  validates :reps, numericality: { greater_than: 0 }, allow_nil: true
  validates :duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validates :weight_unit, inclusion: { in: %w[kg lbs] }
  validate :has_either_reps_or_duration

  # Callbacks
  before_validation :set_defaults

  # Scopes
  scope :by_exercise, ->(name) { where(exercise_name: name) }
  scope :with_weight, -> { where.not(weight: nil) }
  scope :with_reps, -> { where.not(reps: nil) }
  scope :with_duration, -> { where.not(duration_seconds: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def volume
    return 0 unless weight.present? && reps.present?

    weight * reps
  end

  def is_timed_exercise?
    duration_seconds.present?
  end

  def is_weighted_exercise?
    weight.present? && reps.present?
  end

  def duration_formatted
    return nil unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60

    if minutes > 0
      "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
    else
      "#{seconds}s"
    end
  end

  def weight_in_kg
    return weight if weight_unit == "kg"
    return nil unless weight

    (weight * 0.453592).round(2) # Convert lbs to kg
  end

  def weight_in_lbs
    return weight if weight_unit == "lbs"
    return nil unless weight

    (weight * 2.20462).round(2) # Convert kg to lbs
  end

  private

  def set_defaults
    self.weight_unit ||= "kg"
  end

  def has_either_reps_or_duration
    if reps.blank? && duration_seconds.blank?
      errors.add(:base, "Must have either reps or duration")
    end
  end
end
