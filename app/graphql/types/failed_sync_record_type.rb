# frozen_string_literal: true

module Types
  class FailedSyncRecordType < Types::BaseObject
    description "Information about a failed sync record"

    field :client_id, String, null: false, description: "Client ID of the failed record"
    field :error, String, null: false, description: "Human-readable error message"
    field :reason, Types::SyncFailureReasonEnum, null: false, description: "Structured failure reason (R12 — iOS dispatches on this)"
  end
end
