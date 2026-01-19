# frozen_string_literal: true

class WorkoutRecord < ApplicationRecord
  belongs_to :user
  belongs_to :workout_session, optional: true

  validates :date, presence: true
  validates :total_duration, presence: true, numericality: { greater_than: 0 }
  validates :perceived_exertion, presence: true, inclusion: { in: 1..10 }
  validates :completion_status, presence: true

  scope :recent, ->(days = 30) { where("date >= ?", days.days.ago) }
  scope :completed, -> { where(completion_status: "COMPLETED") }

  def duration_in_minutes
    total_duration / 60
  end
end
