# frozen_string_literal: true

# Service for generating S3 presigned URLs for video uploads and downloads
class PresignedUrlService
  DEFAULT_UPLOAD_EXPIRES_IN = 3600   # 1 hour
  DEFAULT_DOWNLOAD_EXPIRES_IN = 3600 # 1 hour
  MAX_VIDEO_SIZE = 500.megabytes

  class << self
    # Generate a presigned URL for uploading a video to S3
    # @param user_id [Integer] User ID for namespacing
    # @param exercise_type [String] Exercise type (pushup, squat, pullup)
    # @param content_type [String] Video content type (e.g., video/mp4)
    # @param expires_in [Integer] URL expiration time in seconds
    # @return [Hash] { upload_url:, video_key:, expires_at: }
    def generate_upload_url(user_id:, exercise_type:, content_type: "video/mp4", expires_in: DEFAULT_UPLOAD_EXPIRES_IN)
      unless AwsConfig.configured?
        return {
          success: false,
          error: "AWS credentials not configured"
        }
      end

      video_key = generate_video_key(user_id, exercise_type)
      expires_at = Time.current + expires_in.seconds

      signer = Aws::S3::Presigner.new(client: AwsConfig.s3_client)

      upload_url = signer.presigned_url(
        :put_object,
        bucket: AwsConfig.s3_bucket,
        key: video_key,
        content_type: content_type,
        expires_in: expires_in,
        metadata: {
          "user-id" => user_id.to_s,
          "exercise-type" => exercise_type,
          "uploaded-at" => Time.current.iso8601
        }
      )

      {
        success: true,
        upload_url: upload_url,
        video_key: video_key,
        expires_at: expires_at.iso8601
      }
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error("[PresignedUrlService] S3 error: #{e.message}")
      { success: false, error: e.message }
    end

    # Generate a presigned URL for downloading/viewing a video from S3
    # @param video_key [String] S3 object key
    # @param expires_in [Integer] URL expiration time in seconds
    # @return [Hash] { download_url:, expires_at: }
    def generate_download_url(video_key, expires_in: DEFAULT_DOWNLOAD_EXPIRES_IN)
      unless AwsConfig.configured?
        return {
          success: false,
          error: "AWS credentials not configured"
        }
      end

      expires_at = Time.current + expires_in.seconds

      signer = Aws::S3::Presigner.new(client: AwsConfig.s3_client)

      download_url = signer.presigned_url(
        :get_object,
        bucket: AwsConfig.s3_bucket,
        key: video_key,
        expires_in: expires_in
      )

      {
        success: true,
        download_url: download_url,
        expires_at: expires_at.iso8601
      }
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error("[PresignedUrlService] S3 error: #{e.message}")
      { success: false, error: e.message }
    end

    # Check if a video exists in S3
    # @param video_key [String] S3 object key
    # @return [Boolean]
    def video_exists?(video_key)
      return false unless AwsConfig.configured?

      AwsConfig.s3_client.head_object(
        bucket: AwsConfig.s3_bucket,
        key: video_key
      )
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error("[PresignedUrlService] S3 error checking video: #{e.message}")
      false
    end

    private

    def generate_video_key(user_id, exercise_type)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      uuid = SecureRandom.uuid[0..7]
      "fitness-tests/#{user_id}/#{exercise_type}_#{timestamp}_#{uuid}.mp4"
    end
  end
end
