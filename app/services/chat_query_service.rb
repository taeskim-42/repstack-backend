# frozen_string_literal: true

# ChatQueryService: Handles natural language record queries
# No AI needed - pure database queries with formatting
class ChatQueryService
  class << self
    def query_records(user:, params:)
      new(user: user).query_records(params)
    end
  end

  def initialize(user:)
    @user = user
  end

  def query_records(params)
    time_range = params[:time_range] || :recent
    exercise_name = params[:exercise_name]
    aggregation = params[:aggregation]

    # Build the query
    sets = build_query(time_range, exercise_name)

    # Get records
    records = format_records(sets)

    # Get summary
    summary = calculate_summary(sets, aggregation)

    # Build interpretation message with record details
    interpretation = build_interpretation(time_range, exercise_name, records.count, records: records, summary: summary)

    {
      success: true,
      records: records,
      summary: summary,
      interpretation: interpretation,
      error: nil
    }
  rescue StandardError => e
    Rails.logger.error("ChatQueryService error: #{e.message}")
    { success: false, error: "기록 조회 실패: #{e.message}" }
  end

  private

  attr_reader :user

  def build_query(time_range, exercise_name)
    sets = user.workout_sets.joins(:workout_session)

    # Apply time range filter
    sets = apply_time_range(sets, time_range)

    # Apply exercise filter if specified
    sets = sets.where("LOWER(exercise_name) LIKE ?", "%#{exercise_name.downcase}%") if exercise_name

    sets.order(created_at: :desc).limit(50)
  end

  def apply_time_range(sets, time_range)
    case time_range
    when :today
      sets.where("workout_sets.created_at >= ?", Date.current.beginning_of_day)
    when :yesterday
      sets.where(
        "workout_sets.created_at >= ? AND workout_sets.created_at < ?",
        Date.yesterday.beginning_of_day,
        Date.current.beginning_of_day
      )
    when :this_week
      sets.where("workout_sets.created_at >= ?", Date.current.beginning_of_week)
    when :last_week
      sets.where(
        "workout_sets.created_at >= ? AND workout_sets.created_at < ?",
        1.week.ago.beginning_of_week,
        Date.current.beginning_of_week
      )
    when :this_month
      sets.where("workout_sets.created_at >= ?", Date.current.beginning_of_month)
    when :last_month
      sets.where(
        "workout_sets.created_at >= ? AND workout_sets.created_at < ?",
        1.month.ago.beginning_of_month,
        Date.current.beginning_of_month
      )
    when :recent
      sets.where("workout_sets.created_at >= ?", 30.days.ago)
    else
      sets.where("workout_sets.created_at >= ?", 30.days.ago)
    end
  end

  def format_records(sets)
    # Group by date and exercise for cleaner output
    grouped = sets.group_by { |s| [ s.created_at.to_date, s.exercise_name ] }

    grouped.map do |(date, exercise_name), exercise_sets|
      total_sets = exercise_sets.count
      avg_weight = exercise_sets.filter_map(&:weight).sum.to_f / total_sets
      avg_reps = exercise_sets.filter_map(&:reps).sum.to_f / total_sets
      volume = exercise_sets.sum { |s| (s.weight || 0) * (s.reps || 0) }

      {
        date: date.strftime("%Y-%m-%d"),
        exercise_name: exercise_name,
        weight: avg_weight.round(1),
        reps: avg_reps.round,
        sets: total_sets,
        volume: volume.round(1),
        recorded_at: exercise_sets.first.created_at.iso8601
      }
    end
  end

  def calculate_summary(sets, aggregation)
    return nil if sets.empty?

    weights = sets.filter_map(&:weight)
    reps = sets.filter_map(&:reps)

    summary = {
      max_weight: weights.max&.to_f,
      max_reps: reps.max,
      avg_weight: weights.any? ? (weights.sum / weights.count.to_f).round(1) : nil,
      total_volume: sets.sum { |s| (s.weight || 0) * (s.reps || 0) }.round(1),
      total_sets: sets.count,
      total_workouts: sets.map { |s| s.workout_session_id }.uniq.count
    }

    # Highlight specific aggregation if requested
    case aggregation
    when :max
      summary[:highlight] = "최고 무게: #{summary[:max_weight]}kg"
    when :avg
      summary[:highlight] = "평균 무게: #{summary[:avg_weight]}kg"
    when :sum
      summary[:highlight] = "총 볼륨: #{summary[:total_volume]}kg"
    when :count
      summary[:highlight] = "총 #{summary[:total_workouts]}회 운동"
    end

    summary
  end

  def build_interpretation(time_range, exercise_name, count, records: [], summary: nil)
    time_desc = case time_range
    when :today then "오늘"
    when :yesterday then "어제"
    when :this_week then "이번주"
    when :last_week then "지난주"
    when :this_month then "이번달"
    when :last_month then "지난달"
    else "최근 30일"
    end

    exercise_desc = exercise_name ? "#{exercise_name} " : ""

    if count.zero?
      "#{time_desc} #{exercise_desc}기록이 없어요."
    else
      # Build detailed message with actual records
      message_parts = ["#{time_desc} #{exercise_desc}기록이에요! 💪"]

      # Add record details (limit to 5 for readability)
      records.first(5).each do |record|
        weight_str = record[:weight] > 0 ? "#{record[:weight]}kg" : "맨몸"
        message_parts << "• #{record[:date]}: #{weight_str} x #{record[:reps]}회 (#{record[:sets]}세트)"
      end

      # Add summary highlight if available
      if summary && summary[:max_weight]
        message_parts << "\n📊 최고 기록: #{summary[:max_weight]}kg"
      end

      message_parts.join("\n")
    end
  end
end
