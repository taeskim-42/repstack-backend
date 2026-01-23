class RoutineExercise < ApplicationRecord
  belongs_to :workout_routine

  # Validations
  validates :exercise_name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :order_index, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sets, numericality: { greater_than: 0 }, allow_nil: true
  validates :reps, numericality: { greater_than: 0 }, allow_nil: true
  validates :weight, numericality: { greater_than: 0 }, allow_nil: true
  validates :bpm, numericality: { in: 60..200 }, allow_nil: true
  validates :rest_duration_seconds, numericality: { greater_than: 0 }, allow_nil: true

  # Scopes
  scope :ordered, -> { order(:order_index) }
  scope :by_muscle, ->(muscle) { where(target_muscle: muscle) }
  scope :with_weight, -> { where.not(weight: nil) }
  scope :cardio, -> { where.not(bpm: nil) }
  scope :strength, -> { where(bpm: nil) }

  # Instance methods
  def estimated_exercise_duration
    return 0 unless sets.present?

    # Base time per set (assuming 1-2 minutes per set including rest)
    base_time_per_set = 90 # seconds
    rest_time = rest_duration_seconds || 60 # default 1 minute rest

    total_time = sets * base_time_per_set + (sets - 1) * rest_time
    total_time / 60 # return in minutes
  end

  def rest_duration_formatted
    return nil unless rest_duration_seconds

    minutes = rest_duration_seconds / 60
    seconds = rest_duration_seconds % 60

    if minutes > 0
      "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
    else
      "#{seconds}s"
    end
  end

  def is_cardio?
    bpm.present?
  end

  def is_strength?
    bpm.nil? && (weight.present? || reps.present?)
  end

  def exercise_summary
    summary = "#{sets}x#{reps}" if sets.present? && reps.present?
    summary += " @ #{weight}kg" if weight.present?
    summary += " (#{bpm} BPM)" if bpm.present?
    summary += " - Rest: #{rest_duration_formatted}" if rest_duration_seconds.present?

    summary || exercise_name
  end

  def target_muscle_group
    case target_muscle&.downcase
    when "chest", "pecs", "pectorals"
      "Chest"
    when "back", "lats", "latissimus", "rhomboids", "traps"
      "Back"
    when "shoulders", "delts", "deltoids"
      "Shoulders"
    when "arms", "biceps", "triceps"
      "Arms"
    when "legs", "quads", "hamstrings", "glutes", "calves"
      "Legs"
    when "core", "abs", "abdominals"
      "Core"
    when "cardio", "conditioning"
      "Cardio"
    else
      target_muscle&.titleize || "Other"
    end
  end

  # Class methods
  def self.muscle_group_distribution
    group(:target_muscle).count
  end

  def self.average_sets_per_exercise
    average(:sets)&.round(1)
  end

  def self.total_estimated_duration
    sum(&:estimated_exercise_duration)
  end
end
