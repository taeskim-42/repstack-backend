# frozen_string_literal: true

module Types
  class QueryRecordsInputType < Types::BaseInputObject
    description "Input for querying workout records"

    argument :query, String, required: false, description: "Natural language query (e.g., '벤치프레스 기록', '이번주 운동')"
    argument :exercise_name, String, required: false, description: "Specific exercise name filter"
    argument :date_range, Types::DateRangeInputType, required: false, description: "Date range filter"
    argument :limit, Integer, required: false, default_value: 50, description: "Maximum number of results"
  end
end
