# frozen_string_literal: true

# Admin controller for background job triggers
# Protected by admin secret token
class AdminController < ApplicationController
  skip_before_action :authorize_request
  before_action :verify_admin_token

  # POST /admin/reanalyze_videos
  # Triggers reanalysis of all videos with timestamp extraction
  # Use ?status=pending|completed|all (default: all)
  def reanalyze_videos
    status = params[:status] || "all"

    videos = case status
    when "pending" then YoutubeVideo.pending
    when "completed" then YoutubeVideo.completed
    else YoutubeVideo.all
    end

    total = videos.count

    videos.find_each do |video|
      ReanalyzeVideoJob.perform_async(video.id)
    end

    render json: {
      success: true,
      message: "Enqueued #{total} videos for reanalysis",
      estimated_hours: (total * 17.0 / 5 / 3600).round(1),
      status_filter: status
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
