# frozen_string_literal: true

module Types
  class SyncOfflineRecordsPayloadType < Types::BaseObject
    description "Response payload for offline records sync"

    field :success, Boolean, null: false
    field :synced_count, Integer, null: false, description: "Number of successfully synced records"
    field :failed_records, [ Types::FailedSyncRecordType ], null: true, description: "List of failed records"
    field :error, String, null: true
  end
end
