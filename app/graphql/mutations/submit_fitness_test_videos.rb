# frozen_string_literal: true

module Mutations
  class SubmitFitnessTestVideos < BaseMutation
    description "Submit video keys for fitness test analysis. Triggers background processing."

    argument :videos, [Types::FitnessVideoInputType], required: true,
      description: "Array of exercise videos to analyze"

    field :submission_id, ID, null: true, description: "ID of the created submission"
    field :job_id, String, null: true, description: "Job ID for tracking progress"
    field :status, Types::FitnessTestSubmissionStatusEnum, null: true, description: "Initial status"
    field :errors, [String], null: false

    # Minimum required videos for a valid submission
    MIN_VIDEOS = 1
    MAX_VIDEOS = 10

    def resolve(videos:)
      user = context[:current_user]
      return auth_error unless user

      # Check if user already has level assessed
      if user.user_profile&.level_assessed_at.present?
        return {
          submission_id: nil,
          job_id: nil,
          status: nil,
          errors: ["이미 레벨이 측정되었습니다. 레벨 변경은 승급 테스트를 통해 진행해주세요."]
        }
      end

      # Check for pending submissions
      pending_submission = user.fitness_test_submissions.where(status: %w[pending processing]).first
      if pending_submission
        return {
          submission_id: nil,
          job_id: nil,
          status: nil,
          errors: ["이미 처리 중인 테스트가 있습니다. 완료될 때까지 기다려주세요."]
        }
      end

      # Validate videos
      validation_errors = validate_videos(videos)
      return { submission_id: nil, job_id: nil, status: nil, errors: validation_errors } if validation_errors.any?

      # Create submission
      job_id = SecureRandom.uuid
      submission = user.fitness_test_submissions.create!(
        job_id: job_id,
        status: "pending",
        videos: videos.map { |v| { "exercise_type" => v.exercise_type, "video_key" => v.video_key } },
        analyses: {}
      )

      # Enqueue background job
      FitnessTestAnalysisJob.perform_later(submission.id)

      Rails.logger.info("[SubmitFitnessTestVideos] Created submission #{submission.id} with #{videos.size} videos")

      {
        submission_id: submission.id,
        job_id: job_id,
        status: submission.status,
        errors: []
      }
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[SubmitFitnessTestVideos] Failed to create submission: #{e.message}")
      { submission_id: nil, job_id: nil, status: nil, errors: ["제출 생성에 실패했습니다."] }
    end

    private

    def auth_error
      { submission_id: nil, job_id: nil, status: nil, errors: ["인증이 필요합니다."] }
    end

    def validate_videos(videos)
      errors = []

      if videos.size < MIN_VIDEOS
        errors << "최소 #{MIN_VIDEOS}개의 영상이 필요합니다."
      end

      if videos.size > MAX_VIDEOS
        errors << "최대 #{MAX_VIDEOS}개의 영상까지 제출 가능합니다."
      end

      # Check for duplicates
      exercise_types = videos.map(&:exercise_type)
      if exercise_types.uniq.size != exercise_types.size
        errors << "중복된 운동 타입이 있습니다."
      end

      # Validate each video
      videos.each do |video|
        unless video.video_key.start_with?("fitness-tests/")
          errors << "#{video.exercise_type} 영상 키 형식이 올바르지 않습니다."
        end

        unless video.exercise_type.match?(/\A[a-z][a-z0-9_]{1,29}\z/)
          errors << "#{video.exercise_type}은(는) 잘못된 운동 타입 형식입니다."
        end
      end

      errors
    end
  end
end
