# frozen_string_literal: true

class WorkoutFeedback < ApplicationRecord
  belongs_to :user

  FEEDBACK_TYPES = %w[DIFFICULTY EFFECTIVENESS ENJOYMENT TIME OTHER].freeze

  validates :feedback_type, presence: true, inclusion: { in: FEEDBACK_TYPES }
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :feedback, presence: true

  scope :recent, ->(days = 30) { where("created_at >= ?", days.days.ago) }
  scope :for_routine, ->(routine_id) { where(routine_id: routine_id) }
  scope :positive, -> { where("rating >= 4") }
  scope :negative, -> { where("rating <= 2") }
end
