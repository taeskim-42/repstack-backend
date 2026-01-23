# frozen_string_literal: true

module Types
  class QueryRecordsPayloadType < Types::BaseObject
    description "Response payload for workout records query"

    field :success, Boolean, null: false
    field :records, [ Types::WorkoutRecordItemType ], null: true
    field :summary, Types::RecordSummaryType, null: true
    field :interpretation, String, null: true, description: "Human-readable interpretation of the query"
    field :error, String, null: true
  end
end
