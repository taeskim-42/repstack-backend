# frozen_string_literal: true

module Mutations
  class CreateFitnessTestUploadUrl < BaseMutation
    description "Generate a presigned URL for uploading a fitness test video to S3"

    argument :exercise_type, String, required: true,
      description: "Type of exercise (e.g., 'pushup', 'squat', 'bench_press', 'deadlift')"
    argument :content_type, String, required: false, default_value: "video/mp4",
      description: "Content type of the video (default: video/mp4)"

    field :upload_url, String, null: true, description: "Presigned URL for uploading"
    field :video_key, String, null: true, description: "S3 key to reference the video later"
    field :expires_at, GraphQL::Types::ISO8601DateTime, null: true, description: "URL expiration time"
    field :errors, [String], null: false

    def resolve(exercise_type:, content_type:)
      user = context[:current_user]
      return auth_error unless user

      # Validate content type
      unless valid_content_type?(content_type)
        return { upload_url: nil, video_key: nil, expires_at: nil, errors: ["지원하지 않는 파일 형식입니다."] }
      end

      # Validate exercise type format
      unless valid_exercise_type?(exercise_type)
        return { upload_url: nil, video_key: nil, expires_at: nil, errors: ["잘못된 운동 타입입니다."] }
      end

      # Check if user already has level assessed
      if user.user_profile&.level_assessed_at.present?
        return {
          upload_url: nil,
          video_key: nil,
          expires_at: nil,
          errors: ["이미 레벨이 측정되었습니다. 레벨 변경은 승급 테스트를 통해 진행해주세요."]
        }
      end

      # Generate presigned URL
      result = PresignedUrlService.generate_upload_url(
        user_id: user.id,
        exercise_type: exercise_type,
        content_type: content_type
      )

      if result[:success]
        {
          upload_url: result[:upload_url],
          video_key: result[:video_key],
          expires_at: result[:expires_at],
          errors: []
        }
      else
        {
          upload_url: nil,
          video_key: nil,
          expires_at: nil,
          errors: [result[:error] || "업로드 URL 생성에 실패했습니다."]
        }
      end
    end

    private

    def auth_error
      { upload_url: nil, video_key: nil, expires_at: nil, errors: ["인증이 필요합니다."] }
    end

    def valid_content_type?(content_type)
      %w[video/mp4 video/quicktime video/x-m4v].include?(content_type)
    end

    def valid_exercise_type?(exercise_type)
      # Allow alphanumeric and underscores, 2-30 chars
      exercise_type.match?(/\A[a-z][a-z0-9_]{1,29}\z/)
    end
  end
end
