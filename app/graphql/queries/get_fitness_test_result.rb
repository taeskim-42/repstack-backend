# frozen_string_literal: true

module Queries
  class GetFitnessTestResult < BaseQuery
    description "Get the result of a fitness test submission by ID or job_id"

    argument :submission_id, ID, required: false,
      description: "ID of the submission"
    argument :job_id, String, required: false,
      description: "Job ID of the submission"

    type Types::FitnessTestSubmissionType, null: true

    def resolve(submission_id: nil, job_id: nil)
      authenticate_user!

      if submission_id.blank? && job_id.blank?
        raise GraphQL::ExecutionError, "submission_id 또는 job_id 중 하나는 필수입니다."
      end

      submission = if submission_id.present?
        current_user.fitness_test_submissions.find_by(id: submission_id)
      else
        current_user.fitness_test_submissions.find_by(job_id: job_id)
      end

      unless submission
        raise GraphQL::ExecutionError, "해당 테스트 제출을 찾을 수 없습니다."
      end

      submission
    end
  end
end
