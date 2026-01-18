class WorkoutSession < ApplicationRecord
  belongs_to :user
  has_many :workout_sets, dependent: :destroy

  # Validations
  validates :start_time, presence: true
  validate :end_time_after_start_time, if: :end_time?
  validate :only_one_active_session_per_user, if: :active?

  # Scopes
  scope :active, -> { where(end_time: nil) }
  scope :completed, -> { where.not(end_time: nil) }
  scope :recent, -> { order(start_time: :desc) }
  scope :for_date, ->(date) { where(start_time: date.beginning_of_day..date.end_of_day) }
  scope :this_week, -> { where(start_time: 1.week.ago..Time.current) }

  # Instance methods
  def active?
    end_time.nil?
  end

  def completed?
    end_time.present?
  end

  def duration_in_seconds
    return nil unless completed?
    
    (end_time - start_time).to_i
  end

  def duration_formatted
    return 'In progress' if active?
    return nil unless duration_in_seconds

    hours = duration_in_seconds / 3600
    minutes = (duration_in_seconds % 3600) / 60

    if hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end

  def total_sets
    workout_sets.count
  end

  def exercises_performed
    workout_sets.distinct.count(:exercise_name)
  end

  def total_volume
    workout_sets.sum('weight * reps')
  end

  def complete!
    update!(end_time: Time.current)
  end

  def add_set(exercise_name:, weight: nil, reps: nil, duration_seconds: nil, notes: nil)
    workout_sets.create!(
      exercise_name: exercise_name,
      weight: weight,
      reps: reps,
      duration_seconds: duration_seconds,
      notes: notes
    )
  end

  private

  def end_time_after_start_time
    return unless end_time && start_time

    errors.add(:end_time, 'must be after start time') if end_time <= start_time
  end

  def only_one_active_session_per_user
    return unless user_id

    existing_active = user.workout_sessions.active.where.not(id: id)
    errors.add(:base, 'User already has an active workout session') if existing_active.exists?
  end
end