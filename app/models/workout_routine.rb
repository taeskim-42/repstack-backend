class WorkoutRoutine < ApplicationRecord
  belongs_to :user
  belongs_to :training_program, optional: true
  has_many :routine_exercises, dependent: :destroy

  # Validations
  validates :level, inclusion: { in: %w[beginner intermediate advanced] }
  validates :week_number, presence: true, numericality: { greater_than: 0 }
  validates :day_number, presence: true, numericality: { in: 1..7 }
  validates :generated_at, presence: true
  validates :estimated_duration, numericality: { greater_than: 0 }, allow_nil: true

  # Callbacks
  before_validation :set_generated_at, on: :create

  # Scopes
  scope :by_level, ->(level) { where(level: level) }
  scope :by_week, ->(week) { where(week_number: week) }
  scope :by_day, ->(day) { where(day_number: day) }
  scope :completed, -> { where(is_completed: true) }
  scope :pending, -> { where(is_completed: false) }
  scope :recent, -> { order(generated_at: :desc) }
  scope :for_program_week, ->(program_id, week) {
    where(training_program_id: program_id, week_number: week)
  }
  scope :baseline, -> { where(generation_source: "program_baseline") }

  # Instance methods
  def complete!
    update!(is_completed: true, completed_at: Time.current)

    # Advance user to next day
    user.user_profile&.advance_day!
  end

  def total_exercises
    routine_exercises.count
  end

  def total_sets
    routine_exercises.sum(:sets)
  end

  def estimated_duration_formatted
    return nil unless estimated_duration

    hours = estimated_duration / 60
    minutes = estimated_duration % 60

    if hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end

  def workout_summary
    muscle_groups = routine_exercises.distinct.pluck(:target_muscle).compact
    exercise_count = total_exercises

    {
      level: level,
      week: week_number,
      day: day_number,
      exercises: exercise_count,
      muscle_groups: muscle_groups,
      estimated_duration: estimated_duration_formatted
    }
  end

  def day_name
    %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday][day_number - 1]
  end

  def day_korean
    %w[월요일 화요일 수요일 목요일 금요일 토요일 일요일][day_number - 1] || "운동"
  end

  # Class methods
  def self.for_user_current_program(user)
    profile = user.user_profile
    return none unless profile

    where(
      user: user,
      level: profile.current_level,
      week_number: profile.week_number,
      day_number: profile.day_number,
      is_completed: false
    )
  end

  private

  def set_generated_at
    self.generated_at ||= Time.current
  end
end
