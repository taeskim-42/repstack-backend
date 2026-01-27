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

  # POST /admin/stop_reanalysis
  # Stop all pending reanalysis jobs
  def stop_reanalysis
    require "sidekiq/api"

    # Clear the reanalysis queue
    queue = Sidekiq::Queue.new("youtube_analysis")
    cleared_count = queue.size
    queue.clear

    # Also clear any scheduled jobs for ReanalyzeVideoJob
    scheduled = Sidekiq::ScheduledSet.new
    scheduled_cleared = scheduled.select { |job| job.klass == "ReanalyzeVideoJob" }.each(&:delete).count

    # Reset analyzing videos back to completed
    analyzing_reset = YoutubeVideo.analyzing.update_all(analysis_status: "completed")

    render json: {
      success: true,
      message: "Reanalysis stopped",
      cleared_queued_jobs: cleared_count,
      cleared_scheduled_jobs: scheduled_cleared,
      reset_analyzing_videos: analyzing_reset
    }
  end

  # GET /admin/sample_knowledge
  # Get random samples of knowledge data for review
  def sample_knowledge
    knowledge_type = params[:type] || "all"
    limit = [params[:limit]&.to_i || 30, 100].min

    scope = if knowledge_type == "all"
              FitnessKnowledgeChunk.all
            else
              FitnessKnowledgeChunk.where(knowledge_type: knowledge_type)
            end

    samples = scope.order("RANDOM()").limit(limit).map do |chunk|
      {
        id: chunk.id,
        type: chunk.knowledge_type,
        exercise_name: chunk.exercise_name,
        muscle_group: chunk.muscle_group,
        summary: chunk.summary&.truncate(200),
        content: chunk.content&.truncate(300)
      }
    end

    render json: {
      total_count: scope.count,
      sample_count: samples.size,
      samples: samples
    }
  end

  # POST /admin/ai_cleanup_knowledge
  # AI-powered cleanup of irrelevant knowledge data
  # Use ?limit=100 (default) and ?dry_run=true to preview
  def ai_cleanup_knowledge
    limit = [params[:limit]&.to_i || 100, 500].min
    dry_run = params[:dry_run] == "true"

    results = KnowledgeCleanupService.cleanup(limit: limit, dry_run: dry_run)

    render json: {
      success: true,
      dry_run: dry_run,
      results: results,
      remaining: FitnessKnowledgeChunk.count
    }
  end

  # DELETE /admin/delete_chunks
  # Delete specific knowledge chunks by IDs
  def delete_chunks
    ids = params[:ids]&.split(",")&.map(&:to_i)
    return render json: { error: "No IDs provided" }, status: :bad_request if ids.blank?

    deleted = FitnessKnowledgeChunk.where(id: ids).destroy_all
    render json: {
      success: true,
      deleted_count: deleted.size,
      deleted_ids: deleted.map(&:id),
      remaining: FitnessKnowledgeChunk.count
    }
  end

  # GET /admin/simulate_beginner
  # Simulate beginner searching for exercises to test knowledge matching
  def simulate_beginner
    exercises = params[:exercises]&.split(",") || nil
    samples = [params[:samples]&.to_i || 5, 10].min

    results = if exercises
                KnowledgeMatchSimulator.run(exercises: exercises, samples_per_exercise: samples)
              else
                KnowledgeMatchSimulator.run(samples_per_exercise: samples)
              end

    render json: {
      success: true,
      simulation: "beginner_exercise_search",
      results: results
    }
  end

  # GET /admin/simulate_all_levels
  # Simulate beginner, intermediate, advanced users in parallel
  def simulate_all_levels
    samples = [params[:samples]&.to_i || 3, 5].min

    results = KnowledgeMatchSimulator.run_all_levels(samples_per_exercise: samples)

    render json: {
      success: true,
      simulation: "all_levels_exercise_search",
      results: results
    }
  end

  # POST /admin/tag_knowledge_levels
  # Tag knowledge chunks with difficulty levels using AI
  def tag_knowledge_levels
    limit = [params[:limit]&.to_i || 100, 500].min

    results = KnowledgeLevelTagger.tag(limit: limit)

    render json: {
      success: true,
      results: results,
      stats: {
        total: FitnessKnowledgeChunk.count,
        beginner: FitnessKnowledgeChunk.where(difficulty_level: "beginner").count,
        intermediate: FitnessKnowledgeChunk.where(difficulty_level: "intermediate").count,
        advanced: FitnessKnowledgeChunk.where(difficulty_level: "advanced").count,
        all: FitnessKnowledgeChunk.where(difficulty_level: "all").count,
        untagged: FitnessKnowledgeChunk.where(difficulty_level: [nil, ""]).count
      }
    }
  end

  # POST /admin/seed_exercises
  # Seed/update exercise data with form_tips
  def seed_exercises
    require_relative "../../db/seeds/exercises"

    before_count = Exercise.count
    seed_exercises_data

    render json: {
      success: true,
      message: "Exercises seeded",
      before_count: before_count,
      after_count: Exercise.count,
      with_form_tips: Exercise.where.not(form_tips: [nil, ""]).count
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
