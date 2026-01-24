# frozen_string_literal: true

module Types
  class FitnessTestSubmissionStatusEnum < Types::BaseEnum
    description "Status of a fitness test submission"

    value "PENDING", "Waiting to be processed", value: "pending"
    value "PROCESSING", "Currently being analyzed", value: "processing"
    value "COMPLETED", "Analysis complete", value: "completed"
    value "FAILED", "Analysis failed", value: "failed"
  end
end
