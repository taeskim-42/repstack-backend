# frozen_string_literal: true

# Admin controller for background job triggers
# Protected by admin secret token
class AdminController < ApplicationController
  before_action :verify_admin_token

  # POST /admin/reanalyze_videos
  # Triggers reanalysis of all completed videos with timestamp extraction
  def reanalyze_videos
    videos = YoutubeVideo.completed
    total = videos.count

    videos.find_each do |video|
      ReanalyzeVideoJob.perform_async(video.id)
    end

    render json: {
      success: true,
      message: "Enqueued #{total} videos for reanalysis",
      estimated_hours: (total * 17.0 / 5 / 3600).round(1)
    }
  end

  # GET /admin/reanalyze_status
  # Check reanalysis progress
  def reanalyze_status
    total = YoutubeVideo.count
    completed = YoutubeVideo.completed.count
    pending = YoutubeVideo.pending.count
    analyzing = YoutubeVideo.analyzing.count
    failed = YoutubeVideo.failed.count

    chunks_with_timestamp = FitnessKnowledgeChunk.where.not(timestamp_start: nil).count
    chunks_total = FitnessKnowledgeChunk.count

    render json: {
      videos: {
        total: total,
        completed: completed,
        pending: pending,
        analyzing: analyzing,
        failed: failed
      },
      chunks: {
        total: chunks_total,
        with_timestamp: chunks_with_timestamp,
        without_timestamp: chunks_total - chunks_with_timestamp
      }
    }
  end

  private

  def verify_admin_token
    token = request.headers["X-Admin-Token"] || params[:admin_token]
    expected = ENV["ADMIN_SECRET_TOKEN"]

    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
