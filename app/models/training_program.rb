# frozen_string_literal: true

# TrainingProgram stores the long-term workout program framework
# Generated dynamically via RAG + LLM after onboarding consultation
#
# Key concept: "Living Routine"
# - Program defines weekly themes and split schedule (framework)
# - Daily routines are generated dynamically based on:
#   - Current week/phase from TrainingProgram
#   - Today's condition (user input)
#   - Recent workout feedback
#   - RAG knowledge search
#
# Example weekly_plan structure:
# {
#   "1-3" => { "phase" => "적응기", "theme" => "기본 동작 학습", "volume_modifier" => 0.8 },
#   "4-8" => { "phase" => "성장기", "theme" => "점진적 과부하", "volume_modifier" => 1.0 },
#   "9-11" => { "phase" => "강화기", "theme" => "고강도 훈련", "volume_modifier" => 1.1 },
#   "12" => { "phase" => "디로드", "theme" => "회복", "volume_modifier" => 0.6 }
# }
#
# Example split_schedule structure:
# {
#   "1" => { "focus" => "상체", "muscles" => ["chest", "back", "shoulders"] },
#   "2" => { "focus" => "하체", "muscles" => ["legs", "core"] },
#   ...
# }
class TrainingProgram < ApplicationRecord
  belongs_to :user
  has_many :workout_routines, dependent: :nullify

  # Status values
  STATUSES = %w[active completed paused].freeze

  # Periodization types
  PERIODIZATION_TYPES = %w[linear undulating block].freeze

  # Validations
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :periodization_type, inclusion: { in: PERIODIZATION_TYPES }, allow_nil: true
  validates :current_week, numericality: { greater_than: 0 }, allow_nil: true
  validates :total_weeks, numericality: { greater_than: 0 }, allow_nil: true

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :completed, -> { where(status: "completed") }
  scope :paused, -> { where(status: "paused") }

  # Get current phase info from weekly_plan
  def current_phase_info
    return nil if weekly_plan.blank? || current_week.nil?

    weekly_plan.each do |week_range, info|
      range = parse_week_range(week_range)
      return info.merge("week_range" => week_range) if range.include?(current_week)
    end

    nil
  end

  # Get current phase name
  def current_phase
    current_phase_info&.dig("phase")
  end

  # Get current volume modifier (for adjusting routine intensity)
  def current_volume_modifier
    current_phase_info&.dig("volume_modifier") || 1.0
  end

  # Get current theme
  def current_theme
    current_phase_info&.dig("theme")
  end

  # Get today's focus based on day of week (1=Monday)
  def today_focus(day_of_week = nil)
    day_of_week ||= Time.current.wday
    # Convert Sunday (0) to 7 for consistent handling
    day_of_week = 7 if day_of_week == 0

    split_schedule[day_of_week.to_s]
  end

  # Check if current week is a deload week
  def deload_week?
    phase = current_phase&.downcase
    phase&.include?("디로드") || phase&.include?("deload") || phase&.include?("회복")
  end

  # Advance to next week
  def advance_week!
    return false if total_weeks.nil? || current_week >= total_weeks

    new_week = current_week + 1

    if new_week > total_weeks
      update!(status: "completed", completed_at: Time.current)
    else
      update!(current_week: new_week)
    end

    true
  end

  # Calculate progress percentage
  def progress_percentage
    return 0 if total_weeks.nil? || total_weeks.zero?
    ((current_week.to_f / total_weeks) * 100).round
  end

  # Check if program is expired (past expected completion)
  def expired?
    return false if started_at.nil? || total_weeks.nil?
    Time.current > started_at + total_weeks.weeks
  end

  # Get routines for a specific week (latest per day_number)
  def routines_for_week(week_number)
    workout_routines.where(week_number: week_number)
      .includes(:routine_exercises)
      .order(:day_number, created_at: :desc)
      .group_by(&:day_number)
      .transform_values(&:first)
      .values
      .sort_by(&:day_number)
  end

  # Get phase info for a specific week from weekly_plan
  def phase_info_for_week(week_number)
    return nil if weekly_plan.blank?

    weekly_plan.each do |week_range, info|
      range = parse_week_range(week_range)
      return info if range.include?(week_number)
    end

    nil
  end

  # Get training days from split_schedule
  def training_days
    return [] if split_schedule.blank?

    rest_keywords = %w[휴식 rest off]
    split_schedule.filter_map do |day_num, info|
      focus = info["focus"] || info[:focus] || ""
      next if rest_keywords.any? { |kw| focus.downcase.include?(kw) }

      { day_number: day_num.to_i, focus: focus, muscles: info["muscles"] || info[:muscles] || [] }
    end.sort_by { |d| d[:day_number] }
  end

  # Check if baseline routines have been generated
  def routines_generated?
    workout_routines.where(generation_source: "program_baseline").exists?
  end

  private

  # Parse week range string like "1-3" or "12" into a Range
  def parse_week_range(range_str)
    range_str = range_str.to_s
    if range_str.include?("-")
      parts = range_str.split("-").map(&:to_i)
      parts[0]..parts[1]
    else
      week = range_str.to_i
      week..week
    end
  end
end
