# frozen_string_literal: true

require "aws-sdk-s3"

# S3-compatible storage client (AWS S3 or Cloudflare R2)
module AwsConfig
  class << self
    def s3_client
      @s3_client ||= build_s3_client
    end

    def s3_bucket
      ENV.fetch("S3_BUCKET_NAME", "repstack-fitness-videos")
    end

    def configured?
      ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
    end

    def r2?
      ENV["S3_ENDPOINT"].present?
    end

    private

    def build_s3_client
      options = {
        region: ENV.fetch("AWS_REGION", "auto"),
        credentials: Aws::Credentials.new(
          ENV["AWS_ACCESS_KEY_ID"],
          ENV["AWS_SECRET_ACCESS_KEY"]
        )
      }

      # Cloudflare R2 requires custom endpoint
      if ENV["S3_ENDPOINT"].present?
        options[:endpoint] = ENV["S3_ENDPOINT"]
        options[:force_path_style] = true
      end

      Aws::S3::Client.new(options)
    end
  end
end
