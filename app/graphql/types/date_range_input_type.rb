# frozen_string_literal: true

module Types
  class DateRangeInputType < Types::BaseInputObject
    description "Date range for filtering records"

    argument :start_date, String, required: false, description: "Start date (ISO 8601)"
    argument :end_date, String, required: false, description: "End date (ISO 8601)"
  end
end
