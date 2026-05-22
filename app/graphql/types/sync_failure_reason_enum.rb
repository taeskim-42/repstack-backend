# frozen_string_literal: true

module Types
  class SyncFailureReasonEnum < Types::BaseEnum
    description "Why an offline record failed to sync (R12 consensus: structured rejection reasons)"

    value "ALREADY_EXISTS", "Record with same client_id already synced — caller can safely drop"
    value "VALIDATION_FAILED", "Record failed model validation (e.g. invalid weight, reps)"
    value "SESSION_CLOSED", "Target offline session no longer accepts writes"
    value "INTERNAL_ERROR", "Unexpected server-side failure — caller should retry with backoff"
  end
end
