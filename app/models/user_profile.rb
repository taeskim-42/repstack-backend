class UserProfile < ApplicationRecord
  belongs_to :user

  # Validations
  validates :current_level, inclusion: { in: %w[beginner intermediate advanced] }
  validates :week_number, presence: true, numericality: { greater_than: 0 }
  validates :day_number, presence: true, numericality: { in: 1..7 }
  validates :height, numericality: { greater_than: 0 }, allow_nil: true
  validates :weight, numericality: { greater_than: 0 }, allow_nil: true
  validates :body_fat_percentage, numericality: { in: 0..100 }, allow_nil: true

  # Callbacks
  before_validation :set_defaults, on: :create

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

  private

  def set_defaults
    self.week_number ||= 1
    self.day_number ||= 1
    self.program_start_date ||= Date.current
  end
end