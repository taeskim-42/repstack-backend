# frozen_string_literal: true

class ConditionLog < ApplicationRecord
  belongs_to :user

  validates :date, presence: true
  validates :energy_level, presence: true, inclusion: { in: 1..5 }
  validates :stress_level, presence: true, inclusion: { in: 1..5 }
  validates :sleep_quality, presence: true, inclusion: { in: 1..5 }
  validates :motivation, presence: true, inclusion: { in: 1..5 }
  validates :available_time, presence: true, numericality: { greater_than: 0 }

  scope :recent, ->(days = 7) { where("date >= ?", days.days.ago) }
  scope :for_date, ->(date) { where(date: date) }

  def average_condition
    (energy_level + (6 - stress_level) + sleep_quality + motivation) / 4.0
  end

  def recommended_intensity_modifier
    avg = average_condition
    0.5 + (avg / 5.0) * 0.5
  end
end
