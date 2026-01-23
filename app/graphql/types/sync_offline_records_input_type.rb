# frozen_string_literal: true

module Types
  class SyncOfflineRecordsInputType < Types::BaseInputObject
    graphql_name "SyncOfflineInput"
    description "Input for syncing offline workout records"

    argument :records, [ Types::OfflineRecordInputType ], required: true, description: "List of offline records to sync"
  end
end
