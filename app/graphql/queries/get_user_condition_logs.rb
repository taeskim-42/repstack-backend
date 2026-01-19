# frozen_string_literal: true

module Queries
  class GetUserConditionLogs < Queries::BaseQuery
    description "Get user's recent condition logs"

    type [ Types::UserConditionLogType ], null: false

    argument :days, Integer, required: false, default_value: 7,
      description: "Number of days to look back"

    def resolve(days:)
      authenticate_user!

      current_user.condition_logs
        .recent(days)
        .order(date: :desc)
        .map do |log|
          {
            user_id: current_user.id,
            date: log.date.iso8601,
            energy_level: log.energy_level,
            stress_level: log.stress_level,
            sleep_quality: log.sleep_quality,
            soreness: log.soreness,
            motivation: log.motivation,
            available_time: log.available_time,
            notes: log.notes,
            created_at: log.created_at.iso8601
          }
        end
    end
  end
end
