class UserProfile < ApplicationRecord
  belongs_to :user

  # Level tier mapping
  LEVEL_TIERS = {
    1 => "beginner", 2 => "beginner",
    3 => "intermediate", 4 => "intermediate", 5 => "intermediate",
    6 => "advanced", 7 => "advanced", 8 => "advanced"
  }.freeze

  # Validations
  validates :current_level, inclusion: { in: %w[beginner intermediate advanced] }
  validates :numeric_level, numericality: { in: 1..8 }, allow_nil: true
  validates :week_number, presence: true, numericality: { greater_than: 0 }
  validates :day_number, presence: true, numericality: { in: 1..7 }
  validates :height, numericality: { greater_than: 0 }, allow_nil: true
  validates :weight, numericality: { greater_than: 0 }, allow_nil: true
  validates :body_fat_percentage, numericality: { in: 0..100 }, allow_nil: true

  # Callbacks
  before_validation :set_defaults, on: :create
  before_save :sync_level_tier

  # Scopes
  scope :by_level, ->(level) { where(current_level: level) }
  scope :beginners, -> { where(current_level: 'beginner') }
  scope :intermediate, -> { where(current_level: 'intermediate') }
  scope :advanced, -> { where(current_level: 'advanced') }

  # Instance methods
  def bmi
    return nil unless height.present? && weight.present?
    
    height_m = height / 100.0
    (weight / (height_m * height_m)).round(1)
  end

  def bmi_category
    case bmi
    when nil
      'Unknown'
    when 0..18.4
      'Underweight'
    when 18.5..24.9
      'Normal'
    when 25.0..29.9
      'Overweight'
    else
      'Obese'
    end
  end

  def days_since_start
    return 0 unless program_start_date.present?
    
    (Date.current - program_start_date).to_i
  end

  def advance_day!
    if day_number < 7
      increment!(:day_number)
    else
      update!(day_number: 1, week_number: week_number + 1)
    end
  end

  def advance_level!
    case current_level
    when 'beginner'
      update!(current_level: 'intermediate', week_number: 1, day_number: 1)
    when 'intermediate'
      update!(current_level: 'advanced', week_number: 1, day_number: 1)
    end
  end

  # Numeric level methods
  def level
    numeric_level || 1
  end

  def level=(value)
    self.numeric_level = value
  end

  def tier
    LEVEL_TIERS[level] || "beginner"
  end

  def tier_korean
    case tier
    when "beginner" then "초급"
    when "intermediate" then "중급"
    when "advanced" then "고급"
    else "초급"
    end
  end

  def grade
    case level
    when 1..3 then "정상인"
    when 4..5 then "건강인"
    when 6..8 then "운동인"
    else "정상인"
    end
  end

  def can_take_level_test?
    return false if level >= 8
    return true if last_level_test_at.nil?

    last_level_test_at < 7.days.ago
  end

  def days_until_next_test
    return 0 if can_take_level_test?

    ((last_level_test_at + 7.days - Time.current) / 1.day).ceil
  end

  def increment_workout_count!
    increment!(:total_workouts_completed)
  end

  private

  def set_defaults
    self.current_level ||= 'beginner'
    self.numeric_level ||= 1
    self.week_number ||= 1
    self.day_number ||= 1
    self.program_start_date ||= Date.current
  end

  def sync_level_tier
    if numeric_level_changed?
      self.current_level = LEVEL_TIERS[numeric_level] || "beginner"
    end
  end
end