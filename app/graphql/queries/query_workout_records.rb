# frozen_string_literal: true

module Queries
  class QueryWorkoutRecords < Queries::BaseQuery
    description "Query workout records with natural language or filters"

    argument :input, Types::QueryRecordsInputType, required: true

    type Types::QueryRecordsPayloadType, null: false

    def resolve(input:)
      authenticate_user!

      # Parse natural language query if provided
      params = parse_query_params(input)

      # Build and execute query
      sets = build_query(params)
      records = format_records(sets)
      summary = calculate_summary(sets)
      interpretation = build_interpretation(params, records.count)

      {
        success: true,
        records: records,
        summary: summary,
        interpretation: interpretation,
        error: nil
      }
    rescue GraphQL::ExecutionError
      raise
    rescue StandardError => e
      Rails.logger.error("QueryWorkoutRecords error: #{e.message}")
      {
        success: false,
        records: nil,
        summary: nil,
        interpretation: nil,
        error: "기록 조회 실패: #{e.message}"
      }
    end

    private

    def parse_query_params(input)
      params = {
        exercise_name: input[:exercise_name],
        limit: input[:limit] || 50
      }

      # Parse date range from input
      if input[:date_range]
        params[:start_date] = Date.parse(input[:date_range][:start_date]) if input[:date_range][:start_date]
        params[:end_date] = Date.parse(input[:date_range][:end_date]) if input[:date_range][:end_date]
      end

      # Parse natural language query
      if input[:query].present?
        parsed = parse_natural_language(input[:query])
        params.merge!(parsed)
      end

      # Default to recent 30 days if no date specified
      params[:start_date] ||= 30.days.ago.to_date
      params[:end_date] ||= Date.current

      params
    end

    def parse_natural_language(query)
      result = {}
      query_lower = query.downcase

      # Time range keywords
      time_ranges = {
        "오늘" => { start_date: Date.current, end_date: Date.current },
        "어제" => { start_date: Date.yesterday, end_date: Date.yesterday },
        "이번주" => { start_date: Date.current.beginning_of_week, end_date: Date.current },
        "지난주" => { start_date: 1.week.ago.beginning_of_week, end_date: 1.week.ago.end_of_week },
        "이번달" => { start_date: Date.current.beginning_of_month, end_date: Date.current },
        "지난달" => { start_date: 1.month.ago.beginning_of_month, end_date: 1.month.ago.end_of_month }
      }

      time_ranges.each do |keyword, range|
        if query_lower.include?(keyword)
          result.merge!(range)
          break
        end
      end

      # Aggregation keywords
      result[:aggregation] = :max if query_lower.match?(/최고|최대/)
      result[:aggregation] = :avg if query_lower.include?("평균")
      result[:aggregation] = :count if query_lower.match?(/몇\s*번|횟수/)

      # Exercise name extraction
      exercise_names = %w[벤치프레스 벤치 스쿼트 데드리프트 데드 풀업 푸시업 런지 숄더프레스 로우 랫풀다운]
      exercise_names.each do |name|
        if query_lower.include?(name)
          result[:exercise_name] = name
          break
        end
      end

      result
    end

    def build_query(params)
      sets = current_user.workout_sets.joins(:workout_session)

      # Date range filter
      if params[:start_date] && params[:end_date]
        sets = sets.where(
          "workout_sets.created_at >= ? AND workout_sets.created_at <= ?",
          params[:start_date].beginning_of_day,
          params[:end_date].end_of_day
        )
      end

      # Exercise name filter
      if params[:exercise_name].present?
        sets = sets.where("LOWER(exercise_name) LIKE ?", "%#{params[:exercise_name].downcase}%")
      end

      sets.order(created_at: :desc).limit(params[:limit])
    end

    def format_records(sets)
      grouped = sets.group_by { |s| [s.created_at.to_date, s.exercise_name] }

      grouped.map do |(date, exercise_name), exercise_sets|
        total_sets = exercise_sets.count
        weights = exercise_sets.filter_map(&:weight)
        reps_list = exercise_sets.filter_map(&:reps)

        {
          date: date.strftime("%Y-%m-%d"),
          exercise_name: exercise_name,
          weight: weights.any? ? (weights.sum / weights.count.to_f).round(1) : nil,
          reps: reps_list.any? ? (reps_list.sum / reps_list.count.to_f).round : nil,
          sets: total_sets,
          volume: exercise_sets.sum { |s| (s.weight || 0) * (s.reps || 0) }.round(1),
          recorded_at: exercise_sets.first.created_at.iso8601
        }
      end
    end

    def calculate_summary(sets)
      return nil if sets.empty?

      weights = sets.filter_map(&:weight)
      reps = sets.filter_map(&:reps)

      {
        max_weight: weights.max&.to_f,
        max_reps: reps.max,
        avg_weight: weights.any? ? (weights.sum / weights.count.to_f).round(1) : nil,
        total_volume: sets.sum { |s| (s.weight || 0) * (s.reps || 0) }.round(1),
        total_sets: sets.count,
        total_workouts: sets.map(&:workout_session_id).uniq.count
      }
    end

    def build_interpretation(params, count)
      parts = []

      # Time description
      if params[:start_date] == Date.current && params[:end_date] == Date.current
        parts << "오늘"
      elsif params[:start_date] == Date.yesterday && params[:end_date] == Date.yesterday
        parts << "어제"
      elsif params[:start_date] == Date.current.beginning_of_week
        parts << "이번주"
      elsif params[:end_date] && params[:end_date] < Date.current.beginning_of_week
        parts << "지난주"
      else
        parts << "#{params[:start_date]&.strftime('%m/%d')} ~ #{params[:end_date]&.strftime('%m/%d')}"
      end

      # Exercise name
      parts << params[:exercise_name] if params[:exercise_name]

      # Result
      base = parts.join(" ")
      if count.zero?
        "#{base} 기록이 없어요."
      else
        "#{base} 기록이에요 (#{count}건)"
      end
    end
  end
end
