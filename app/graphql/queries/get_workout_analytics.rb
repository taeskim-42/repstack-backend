# frozen_string_literal: true

module Queries
  class GetWorkoutAnalytics < Queries::BaseQuery
    description "Get workout analytics and statistics"

    type Types::WorkoutAnalyticsType, null: false

    argument :days, Integer, required: false, default_value: 30,
      description: "Number of days to analyze"

    def resolve(days:)
      authenticate_user!

      records = current_user.workout_records.recent(days)
      sessions = current_user.workout_sessions.where("start_time >= ?", days.days.ago)

      total_workouts = records.count
      total_time = records.sum(:total_duration) / 60 # Convert to minutes
      avg_rpe = records.average(:perceived_exertion)&.to_f || 0.0
      completed_count = records.completed.count
      completion_rate = total_workouts > 0 ? (completed_count.to_f / total_workouts) : 0.0

      # Calculate workout frequency (workouts per week)
      weeks = days / 7.0
      workout_frequency = weeks > 0 ? (total_workouts / weeks) : 0.0

      # Calculate muscle group distribution from workout sets
      muscle_distribution = calculate_muscle_distribution(sessions)

      # Calculate progression trends
      progression_trends = calculate_progression_trends(sessions)

      {
        total_workouts: total_workouts,
        total_time: total_time,
        average_rpe: avg_rpe.round(1),
        completion_rate: completion_rate.round(2),
        workout_frequency: workout_frequency.round(1),
        muscle_group_distribution: muscle_distribution,
        progression_trends: progression_trends
      }
    end

    private

    def calculate_muscle_distribution(sessions)
      sets = WorkoutSet.where(workout_session: sessions)
      return {} if sets.empty?

      distribution = sets.group(:target_muscle).count
      total = sets.count.to_f

      distribution.transform_values { |count| (count / total).round(2) }
    end

    def calculate_progression_trends(sessions)
      sets = WorkoutSet.where(workout_session: sessions)
        .where.not(weight: nil)
        .order(:created_at)

      trends = {}

      sets.group_by(&:exercise_name).each do |exercise, exercise_sets|
        next if exercise_sets.size < 2

        trends[exercise] = {
          "dates" => exercise_sets.map { |s| s.created_at.to_date.iso8601 },
          "weights" => exercise_sets.map(&:weight),
          "reps" => exercise_sets.map(&:reps),
          "volumes" => exercise_sets.map { |s| (s.weight || 0) * (s.reps || 0) }
        }
      end

      trends
    end
  end
end
