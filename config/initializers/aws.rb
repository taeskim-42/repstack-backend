# frozen_string_literal: true

require "aws-sdk-s3"

Aws.config.update({
  region: ENV.fetch("AWS_REGION", "ap-northeast-2"),
  credentials: Aws::Credentials.new(
    ENV["AWS_ACCESS_KEY_ID"],
    ENV["AWS_SECRET_ACCESS_KEY"]
  )
})

# S3 client singleton
module AwsConfig
  class << self
    def s3_client
      @s3_client ||= Aws::S3::Client.new
    end

    def s3_bucket
      ENV.fetch("S3_BUCKET_NAME", "repstack-fitness-videos")
    end

    def configured?
      ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
    end
  end
end
