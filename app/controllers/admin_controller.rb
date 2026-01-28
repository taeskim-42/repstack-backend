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

  # GET /admin/worker_status
  # Check Sidekiq worker status
  def worker_status
    require "sidekiq/api"

    stats = Sidekiq::Stats.new
    processes = Sidekiq::ProcessSet.new

    # Get queue sizes
    queues = Sidekiq::Queue.all.map do |q|
      { name: q.name, size: q.size }
    end

    # Get currently processing jobs
    workers = Sidekiq::Workers.new
    current_jobs = workers.map do |process_id, thread_id, work|
      {
        queue: work["queue"],
        class: work["payload"]["class"],
        args: work["payload"]["args"]&.first(2),
        started_at: Time.at(work["run_at"]).iso8601
      }
    end

    render json: {
      processed: stats.processed,
      failed: stats.failed,
      queues: queues,
      workers_count: workers.size,
      current_jobs: current_jobs.first(5)
    }
  end

  # POST /admin/stop_transcript_extraction
  # Stop transcript extraction jobs
  def stop_transcript_extraction
    require "sidekiq/api"

    # Clear the low queue (where ExtractTranscriptsJob runs)
    queue = Sidekiq::Queue.new("low")
    cleared_count = queue.size
    queue.clear

    # Clear scheduled ExtractTranscriptsJob
    scheduled = Sidekiq::ScheduledSet.new
    scheduled_cleared = scheduled.select { |job| job.klass == "ExtractTranscriptsJob" }.each(&:delete).count

    render json: {
      success: true,
      message: "Transcript extraction stopped",
      cleared_queued_jobs: cleared_count,
      cleared_scheduled_jobs: scheduled_cleared
    }
  end

  # POST /admin/seed_channels
  # Seed all configured YouTube channels
  def seed_channels
    YoutubeChannel.seed_configured_channels!

    channels = YoutubeChannel.all.map do |c|
      { name: c.name, handle: c.handle, language: c.language }
    end

    render json: {
      success: true,
      channels: channels,
      total: channels.count
    }
  end

  # POST /admin/bulk_import_videos
  # Import videos from yt-dlp extracted data
  # Body: { channel_handle: "jeffnippard", videos: [{ video_id: "xxx", title: "...", upload_date: "2024-01-01" }] }
  def bulk_import_videos
    channel_handle = params[:channel_handle]
    videos_data = params[:videos]

    channel = YoutubeChannel.find_by(handle: channel_handle)
    unless channel
      return render json: { error: "Channel not found: #{channel_handle}" }, status: :not_found
    end

    imported = 0
    skipped = 0

    videos_data.each do |video|
      existing = channel.youtube_videos.find_by(video_id: video[:video_id])
      if existing
        skipped += 1
        next
      end

      channel.youtube_videos.create!(
        video_id: video[:video_id],
        title: video[:title] || "Untitled",
        published_at: video[:upload_date],
        analysis_status: "pending"
      )
      imported += 1
    rescue StandardError => e
      Rails.logger.warn("Failed to import video #{video[:video_id]}: #{e.message}")
    end

    channel.mark_synced!

    render json: {
      success: true,
      channel: channel.name,
      imported: imported,
      skipped: skipped,
      total_videos: channel.youtube_videos.count
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

  # GET /admin/list_knowledge
  # List all knowledge with pagination for export
  def list_knowledge
    knowledge_type = params[:type] || "all"
    page = [params[:page]&.to_i || 1, 1].max
    per_page = [params[:per_page]&.to_i || 100, 500].min

    scope = if knowledge_type == "all"
              FitnessKnowledgeChunk.all
            else
              FitnessKnowledgeChunk.where(knowledge_type: knowledge_type)
            end

    total_count = scope.count
    total_pages = (total_count.to_f / per_page).ceil

    chunks = scope.order(id: :desc).offset((page - 1) * per_page).limit(per_page).map do |chunk|
      {
        id: chunk.id,
        type: chunk.knowledge_type,
        difficulty: chunk.difficulty_level,
        exercise_name: chunk.exercise_name,
        muscle_group: chunk.muscle_group,
        summary: chunk.summary,
        content: chunk.content,
        video_title: chunk.youtube_video&.title,
        created_at: chunk.created_at&.iso8601
      }
    end

    render json: {
      data: chunks,
      pagination: {
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages
      }
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

  # GET /admin/test_subtitle_extraction
  # Test subtitle extraction with timestamps for debugging
  def test_subtitle_extraction
    url = params[:url]
    return render json: { error: "url parameter required" }, status: :bad_request unless url

    # Extract subtitles
    transcript = YoutubeChannelScraper.extract_subtitles(url)

    if transcript.blank?
      return render json: { error: "No subtitles found", url: url }
    end

    # Show first 2000 chars of transcript to verify timestamps
    render json: {
      success: true,
      url: url,
      transcript_length: transcript.length,
      transcript_preview: transcript[0..2000],
      has_timestamps: transcript.include?("["),
      sample_timestamps: transcript.scan(/\[\d{2}:\d{2}\]/).first(10)
    }
  end

  # POST /admin/test_knowledge_extraction
  # Test full knowledge extraction on a video URL (extracts transcript + analyzes with Claude)
  def test_knowledge_extraction
    url = params[:url]
    return render json: { error: "url parameter required" }, status: :bad_request unless url

    unless YoutubeKnowledgeExtractionService.configured?
      return render json: { error: "ANTHROPIC_API_KEY not configured" }, status: :unprocessable_entity
    end

    # Step 1: Extract transcript
    transcript = YoutubeChannelScraper.extract_subtitles(url)

    if transcript.blank?
      return render json: { error: "No subtitles found", url: url }
    end

    # Step 2: Analyze with Claude
    result = YoutubeKnowledgeExtractionService.analyze_transcript(transcript)

    # Check timestamps in result
    chunks_with_ts = result[:knowledge_chunks]&.select { |c| c[:timestamp_start].present? } || []

    render json: {
      success: true,
      url: url,
      transcript_length: transcript.length,
      total_chunks: result[:knowledge_chunks]&.count || 0,
      chunks_with_timestamp: chunks_with_ts.count,
      sample_chunks: result[:knowledge_chunks]&.first(3)&.map do |c|
        {
          type: c[:type],
          summary: c[:summary],
          timestamp_start: c[:timestamp_start],
          timestamp_end: c[:timestamp_end]
        }
      end
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

  # POST /admin/import_program_knowledge
  # Import workout programs from workout_programs.rb into RAG knowledge base
  def import_program_knowledge
    imported_count = 0

    # Create virtual YouTube channel/video for program knowledge
    channel = YoutubeChannel.find_or_create_by!(channel_id: "PROGRAM_KNOWLEDGE") do |c|
      c.name = "운동 프로그램 지식"
      c.handle = "@program_knowledge"
      c.url = "internal://program-knowledge"
      c.subscriber_count = 0
      c.video_count = 0
    end

    video = YoutubeVideo.find_or_create_by!(youtube_channel: channel, video_id: "PROGRAM_TEMPLATES") do |v|
      v.title = "운동 프로그램 템플릿"
      v.duration_seconds = 0
      v.analysis_status = "completed"
    end

    # Import programs
    errors = []
    [
      [AiTrainer::WorkoutPrograms::BEGINNER, "beginner"],
      [AiTrainer::WorkoutPrograms::INTERMEDIATE, "intermediate"],
      [AiTrainer::WorkoutPrograms::ADVANCED, "advanced"]
    ].each do |program, difficulty|
      begin
        imported_count += import_program(video, program, difficulty)
      rescue StandardError => e
        errors << "#{difficulty}: #{e.message}"
        Rails.logger.error("Import error for #{difficulty}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      end
    end

    # Import special programs
    begin
      # SHIMHYUNDO has program structure like BEGINNER/INTERMEDIATE/ADVANCED
      if defined?(AiTrainer::WorkoutPrograms::SHIMHYUNDO)
        shimhyundo = AiTrainer::WorkoutPrograms::SHIMHYUNDO
        imported_count += import_shimhyundo_program(video, shimhyundo)
      end
    rescue StandardError => e
      errors << "SHIMHYUNDO: #{e.message}"
      Rails.logger.error("Import error for SHIMHYUNDO: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end

    begin
      # KIMSUNGHWAN has phases structure
      if defined?(AiTrainer::WorkoutPrograms::KIMSUNGHWAN)
        kimsunghwan = AiTrainer::WorkoutPrograms::KIMSUNGHWAN
        imported_count += import_kimsunghwan_program(video, kimsunghwan)
      end
    rescue StandardError => e
      errors << "KIMSUNGHWAN: #{e.message}"
      Rails.logger.error("Import error for KIMSUNGHWAN: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end

    render json: {
      success: errors.empty?,
      message: "Imported #{imported_count} program knowledge chunks",
      imported_count: imported_count,
      total_knowledge_chunks: FitnessKnowledgeChunk.count,
      routine_design_chunks: FitnessKnowledgeChunk.where(knowledge_type: "routine_design").count,
      errors: errors
    }
  end

  # POST /admin/import_knowledge_chunk
  # Import a single knowledge chunk from external source (Excel, etc.)
  def import_knowledge_chunk
    # Find or create the external knowledge video
    channel = YoutubeChannel.find_or_create_by!(channel_id: "EXTERNAL_KNOWLEDGE") do |c|
      c.name = "외부 지식 소스"
      c.handle = "@external_knowledge"
      c.url = "internal://external-knowledge"
      c.subscriber_count = 0
      c.video_count = 0
    end

    video = YoutubeVideo.find_or_create_by!(youtube_channel: channel, video_id: "EXTERNAL_DATA") do |v|
      v.title = "외부 데이터 소스"
      v.duration_seconds = 0
      v.analysis_status = "completed"
    end

    chunk = FitnessKnowledgeChunk.create!(
      youtube_video: video,
      knowledge_type: params[:knowledge_type] || "routine_design",
      content: params[:content],
      summary: params[:summary],
      exercise_name: params[:exercise_name],
      difficulty_level: params[:difficulty_level] || "all",
      timestamp_start: 0
    )

    render json: {
      success: true,
      chunk_id: chunk.id,
      message: "Knowledge chunk created"
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # GET /admin/check_pgvector
  # Check if pgvector is available and what extensions exist
  def check_pgvector
    available_extensions = ActiveRecord::Base.connection.execute(
      "SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name LIKE '%vector%' OR name = 'vector'"
    ).to_a

    installed_extensions = ActiveRecord::Base.connection.execute(
      "SELECT extname, extversion FROM pg_extension"
    ).to_a

    # Try to enable vector extension
    enable_result = begin
      ActiveRecord::Base.connection.execute("CREATE EXTENSION IF NOT EXISTS vector")
      { success: true, message: "Extension enabled or already exists" }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Check if embedding column exists
    columns = ActiveRecord::Base.connection.columns("fitness_knowledge_chunks").map(&:name)

    render json: {
      available_extensions: available_extensions,
      installed_extensions: installed_extensions,
      enable_vector_result: enable_result,
      embedding_column_exists: columns.include?("embedding"),
      all_columns: columns
    }
  end

  # GET /admin/embedding_status
  # Check embedding status and trigger embedding generation
  def embedding_status
    total = FitnessKnowledgeChunk.count
    embedding_column_exists = FitnessKnowledgeChunk.column_names.include?("embedding")

    with_embedding = embedding_column_exists ? FitnessKnowledgeChunk.where.not(embedding: nil).count : 0
    without_embedding = total - with_embedding

    render json: {
      total_chunks: total,
      with_embedding: with_embedding,
      without_embedding: without_embedding,
      coverage_percent: total > 0 ? (with_embedding.to_f / total * 100).round(1) : 0,
      embedding_column_exists: embedding_column_exists,
      pgvector_available: EmbeddingService.pgvector_available?,
      gemini_configured: EmbeddingService.configured?
    }
  end

  # POST /admin/generate_embeddings
  # Generate embeddings for chunks without them
  def generate_embeddings
    limit = [params[:limit]&.to_i || 100, 500].min

    unless FitnessKnowledgeChunk.column_names.include?("embedding")
      return render json: { success: false, error: "Embedding column does not exist. Run migrations first." }, status: :unprocessable_entity
    end

    unless EmbeddingService.configured?
      return render json: { success: false, error: "Gemini API not configured" }, status: :unprocessable_entity
    end

    unless EmbeddingService.pgvector_available?
      return render json: { success: false, error: "pgvector not available" }, status: :unprocessable_entity
    end

    # Run in background or synchronously based on limit
    if limit <= 50
      count = 0
      FitnessKnowledgeChunk.where(embedding: nil).limit(limit).find_each do |chunk|
        EmbeddingService.embed_knowledge_chunk(chunk)
        count += 1
      rescue StandardError => e
        Rails.logger.error("Failed to embed chunk #{chunk.id}: #{e.message}")
      end

      render json: {
        success: true,
        embedded_count: count,
        remaining: FitnessKnowledgeChunk.where(embedding: nil).count
      }
    else
      # Queue for background processing
      GenerateEmbeddingsJob.perform_async(limit) if defined?(GenerateEmbeddingsJob)

      render json: {
        success: true,
        message: "Embedding generation queued",
        limit: limit
      }
    end
  end

  # POST /admin/test_search
  # Test RAG search with a query - uses SAME logic as CreativeRoutineGenerator
  def test_search
    query = params[:query]
    return render json: { error: "query parameter required" }, status: :bad_request unless query.present?

    search_type = params[:search_type] || "semantic" # semantic, keyword
    knowledge_type = params[:knowledge_type] || "all"
    limit = [params[:limit]&.to_i || 10, 30].min
    user_level = params[:level]&.to_i || 3

    # Check if embedding column exists
    embedding_column_exists = FitnessKnowledgeChunk.column_names.include?("embedding")

    debug_info = {
      total_chunks: FitnessKnowledgeChunk.count,
      chunks_with_embedding: embedding_column_exists ? FitnessKnowledgeChunk.where.not(embedding: nil).count : 0,
      embedding_column_exists: embedding_column_exists,
      pgvector_available: EmbeddingService.pgvector_available?,
      gemini_configured: EmbeddingService.configured?,
      user_level: user_level,
      search_query_used: nil,
      actual_search_type: nil
    }

    # Use CreativeRoutineGenerator's search logic
    results, actual_type, search_query = search_like_routine_generator(
      query: query,
      search_type: search_type,
      knowledge_type: knowledge_type,
      limit: limit,
      user_level: user_level
    )

    debug_info[:actual_search_type] = actual_type
    debug_info[:search_query_used] = search_query

    render json: {
      success: true,
      query: query,
      search_type: actual_type,
      requested_search_type: search_type,
      knowledge_type: knowledge_type,
      result_count: results.size,
      results: results,
      debug: debug_info
    }
  rescue StandardError => e
    Rails.logger.error("Search test error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { success: false, error: e.message, backtrace: e.backtrace.first(3) }, status: :internal_server_error
  end

  # POST /admin/extract_transcripts
  # Trigger transcript extraction for videos without transcripts
  # Use ?limit=100 (default)
  def extract_transcripts
    limit = [params[:limit]&.to_i || 100, 500].min
    language = params[:language] # "en", "ko", or nil for all

    scope = YoutubeVideo.where(transcript: [nil, ""])
    scope = scope.joins(:youtube_channel).where(youtube_channels: { language: language }) if language.present?
    without_transcript = scope.count

    if without_transcript == 0
      return render json: {
        success: true,
        message: "All videos already have transcripts",
        without_transcript: 0,
        language_filter: language
      }
    end

    ExtractTranscriptsJob.perform_async(limit, true, language)

    render json: {
      success: true,
      message: "Transcript extraction started",
      without_transcript: without_transcript,
      processing_limit: limit,
      estimated_minutes: (limit * 5.0 / 60).round(1)
    }
  end

  # GET /admin/transcript_status
  # Check transcript extraction progress
  def transcript_status
    total = YoutubeVideo.count
    with_transcript = YoutubeVideo.where.not(transcript: [nil, ""]).count
    without_transcript = total - with_transcript

    render json: {
      total: total,
      with_transcript: with_transcript,
      without_transcript: without_transcript,
      coverage_percent: (with_transcript.to_f / total * 100).round(1)
    }
  end

  # GET /admin/channel_status
  # Check videos per channel
  def channel_status
    channels = YoutubeChannel.all.map do |channel|
      videos = channel.youtube_videos
      with_transcript = videos.where.not(transcript: [nil, ""]).count
      {
        name: channel.name,
        handle: channel.handle,
        language: channel.language,
        total_videos: videos.count,
        with_transcript: with_transcript,
        active: channel.active
      }
    end

    render json: {
      channels: channels,
      total_channels: channels.count
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

  def import_program(video, program, difficulty)
    count = 0
    program_name = program[:korean] || program[:level]
    program_data = program[:program]

    return 0 unless program_data.is_a?(Hash)

    program_data.each do |week_num, week_data|
      next unless week_data.is_a?(Hash)

      week_data.each do |day_num, day_data|
        next unless day_data.is_a?(Hash)

        training_type = day_data[:training_type]
        training_info = AiTrainer::WorkoutPrograms::TRAINING_TYPES[training_type] || {}

        content = build_day_content(program_name, week_num, day_num, day_data, training_info)
        exercises = day_data[:exercises] || []
        exercise_names = exercises.map { |ex| ex[:name] }.join(", ")

        FitnessKnowledgeChunk.find_or_create_by!(
          youtube_video: video,
          knowledge_type: "routine_design",
          summary: "#{program_name} #{week_num}주차 #{day_num}일: #{training_info[:korean] || training_type}"
        ) do |chunk|
          chunk.content = content
          chunk.exercise_name = exercise_names
          chunk.difficulty_level = difficulty
          chunk.timestamp_start = 0
        end
        count += 1
      end
    end
    count
  end

  def build_day_content(program_name, week_num, day_num, day_data, training_info)
    lines = []
    lines << "## #{program_name} - #{week_num}주차 #{day_num}일차"
    lines << ""
    lines << "### 훈련 유형: #{training_info[:korean] || day_data[:training_type]}"
    lines << training_info[:description] if training_info[:description]
    lines << ""
    lines << "### 운동 목록"

    exercises = day_data[:exercises] || []
    exercises.each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      details << "BPM #{ex[:bpm]}" if ex[:bpm]
      details << "무게: #{ex[:weight]}" if ex[:weight]
      details << "ROM: #{ex[:rom]}" if ex[:rom]

      exercise_line += " - #{details.join(', ')}" if details.any?
      exercise_line += "\n   방법: #{ex[:how_to]}" if ex[:how_to]

      lines << exercise_line
    end

    if day_data[:purpose]
      lines << ""
      lines << "### 목적"
      lines << day_data[:purpose]
    end

    lines.join("\n")
  end

  def import_shimhyundo_program(video, program)
    count = 0
    program_name = program[:name] || "심현도 무분할"
    program_data = program[:program]

    return 0 unless program_data.is_a?(Hash)

    program_data.each do |level_num, level_data|
      next unless level_data.is_a?(Hash)

      level_data.each do |day_num, day_data|
        next unless day_data.is_a?(Hash)

        exercises = day_data[:exercises] || []
        exercise_names = exercises.map { |ex| ex[:name] }.join(", ")

        content = build_shimhyundo_content(program_name, level_num, day_num, exercises)

        FitnessKnowledgeChunk.find_or_create_by!(
          youtube_video: video,
          knowledge_type: "routine_design",
          summary: "#{program_name} 레벨#{level_num} #{day_num}일차"
        ) do |chunk|
          chunk.content = content
          chunk.exercise_name = exercise_names
          chunk.difficulty_level = level_num <= 3 ? "beginner" : (level_num <= 5 ? "intermediate" : "advanced")
          chunk.timestamp_start = 0
        end
        count += 1
      end
    end
    count
  end

  def build_shimhyundo_content(program_name, level_num, day_num, exercises)
    lines = []
    lines << "## #{program_name} - 레벨 #{level_num} #{day_num}일차"
    lines << ""
    lines << "### 운동 목록"

    exercises.each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      details << "무게: #{ex[:weight]}" if ex[:weight]

      exercise_line += " - #{details.join(', ')}" if details.any?
      exercise_line += "\n   방법: #{ex[:how_to]}" if ex[:how_to]

      lines << exercise_line
    end

    lines.join("\n")
  end

  def import_kimsunghwan_program(video, program)
    count = 0
    program_name = program[:name] || "김성환 운동 루틴"
    phases = program[:phases]

    return 0 unless phases.is_a?(Hash)

    phases.each do |phase_key, phase_data|
      next unless phase_data.is_a?(Hash)

      phase_name = phase_data[:name] || phase_key.to_s
      exercises = phase_data[:exercises] || []
      exercise_names = exercises.map { |ex| ex[:name] }.join(", ")

      content = build_kimsunghwan_content(program_name, phase_name, phase_data, exercises)

      FitnessKnowledgeChunk.find_or_create_by!(
        youtube_video: video,
        knowledge_type: "routine_design",
        summary: "#{program_name} - #{phase_name}"
      ) do |chunk|
        chunk.content = content
        chunk.exercise_name = exercise_names
        chunk.difficulty_level = phase_key.to_s.include?("beginner") ? "beginner" : (phase_key.to_s.include?("intermediate") ? "intermediate" : "advanced")
        chunk.timestamp_start = 0
      end
      count += 1
    end
    count
  end

  def build_kimsunghwan_content(program_name, phase_name, phase_data, exercises)
    lines = []
    lines << "## #{program_name} - #{phase_name}"
    lines << ""
    lines << "- 기간: #{phase_data[:duration]}" if phase_data[:duration]
    lines << "- 빈도: #{phase_data[:frequency]}" if phase_data[:frequency]
    lines << "- 포커스: #{phase_data[:focus]}" if phase_data[:focus]
    lines << ""
    lines << "### 운동 목록"

    exercises.each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]

      exercise_line += " - #{details.join(', ')}" if details.any?
      lines << exercise_line
    end

    lines.join("\n")
  end

  def import_special_program(video, program, name)
    content = build_special_program_content(program, name)

    FitnessKnowledgeChunk.find_or_create_by!(
      youtube_video: video,
      knowledge_type: "routine_design",
      summary: "#{name} 루틴 프로그램"
    ) do |chunk|
      chunk.content = content
      chunk.exercise_name = extract_all_exercises(program)
      chunk.difficulty_level = "all"
      chunk.timestamp_start = 0
    end
  end

  def build_special_program_content(program, name)
    lines = ["## #{name} 운동 프로그램", ""]

    if program[:description]
      lines << program[:description]
      lines << ""
    end

    if program[:levels]
      program[:levels].each do |level_num, level_data|
        lines << "### 레벨 #{level_num}"
        lines.concat(format_exercises(level_data[:exercises])) if level_data[:exercises]
        lines << ""
      end
    elsif program[:phases]
      program[:phases].each do |phase_name, phase_data|
        lines << "### #{phase_name} 페이즈"
        lines.concat(format_exercises(phase_data[:exercises])) if phase_data[:exercises]
        lines << ""
      end
    end

    lines.join("\n")
  end

  def format_exercises(exercises)
    return [] unless exercises

    exercises.map.with_index do |ex, idx|
      line = "#{idx + 1}. #{ex[:name]}"
      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      line += " - #{details.join(', ')}" if details.any?
      line
    end
  end

  def extract_all_exercises(program)
    exercises = []

    if program[:levels]
      program[:levels].each_value do |level_data|
        exercises.concat(level_data[:exercises]&.map { |ex| ex[:name] } || [])
      end
    elsif program[:phases]
      program[:phases].each_value do |phase_data|
        exercises.concat(phase_data[:exercises]&.map { |ex| ex[:name] } || [])
      end
    end

    exercises.uniq.join(", ")
  end

  # Search using the SAME logic as CreativeRoutineGenerator
  def search_like_routine_generator(query:, search_type:, knowledge_type:, limit:, user_level:)
    # Translate query to English for better embedding search
    english_query = translate_query_for_embedding(query)

    # Extract target muscles from query (same as CreativeRoutineGenerator)
    target_muscles = extract_target_muscles_from_query(query)

    # Build search query in English for embedding compatibility
    tier = AiTrainer::Constants.tier_for_level(user_level)
    search_query = "#{english_query} exercise workout fitness #{tier}"

    actual_type = search_type
    results = []

    # Determine which knowledge types to search
    types_to_search = if knowledge_type == "all"
                        %w[routine_design exercise_technique]
                      else
                        [knowledge_type]
                      end

    types_to_search.each do |ktype|
      chunks, used_type = search_chunks_like_generator(
        query: search_query,
        knowledge_type: ktype,
        limit: limit / types_to_search.size,
        user_level: user_level,
        target_muscles: target_muscles,
        force_keyword: search_type == "keyword"
      )
      actual_type = used_type
      results += chunks
    end

    formatted_results = results.map do |chunk|
      {
        id: chunk[:id],
        type: chunk[:knowledge_type],
        difficulty: chunk[:difficulty_level],
        exercise_name: chunk[:exercise_name],
        muscle_group: chunk[:muscle_group],
        summary: chunk[:summary],
        content: chunk[:content]&.truncate(500),
        has_embedding: chunk[:has_embedding],
        similarity_score: chunk[:similarity_score],
        source: {
          video_title: chunk[:video_title],
          channel: chunk[:channel_name]
        }
      }
    end

    [formatted_results, actual_type, search_query]
  end

  # Same logic as CreativeRoutineGenerator#search_with_embeddings
  def search_chunks_like_generator(query:, knowledge_type:, limit:, user_level:, target_muscles:, force_keyword: false)
    embedding_column_exists = FitnessKnowledgeChunk.column_names.include?("embedding")
    actual_type = "keyword"

    # Try semantic search first (if not forced keyword and embeddings available)
    if !force_keyword && embedding_column_exists && EmbeddingService.pgvector_available? && EmbeddingService.configured?
      begin
        query_embedding = EmbeddingService.generate_query_embedding(query)

        if query_embedding.present?
          # Hybrid search: semantic + muscle_group filter
          base_scope = FitnessKnowledgeChunk
            .where(knowledge_type: knowledge_type)
            .where.not(embedding: nil)
            .for_user_level(user_level)
            .includes(:youtube_video)

          # Apply muscle_group filter if target muscles specified
          if target_muscles.any?
            muscle_conditions = target_muscles.map { "muscle_group ILIKE ?" }
            muscle_values = target_muscles.map { |m| "%#{m}%" }
            base_scope = base_scope.where(muscle_conditions.join(" OR "), *muscle_values)
          end

          chunks = base_scope
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)

          if chunks.any?
            actual_type = target_muscles.any? ? "semantic+muscle_filter" : "semantic"
            results = chunks.map do |c|
              {
                id: c.id,
                knowledge_type: c.knowledge_type,
                difficulty_level: c.difficulty_level,
                exercise_name: c.exercise_name,
                muscle_group: c.muscle_group,
                summary: c.summary,
                content: c.content,
                has_embedding: true,
                similarity_score: c.respond_to?(:neighbor_distance) ? (1 - c.neighbor_distance).round(4) : nil,
                video_title: c.youtube_video&.title,
                channel_name: c.youtube_video&.youtube_channel&.name
              }
            end
            return [results, actual_type]
          end
        end
      rescue StandardError => e
        Rails.logger.warn("Semantic search failed: #{e.message}")
      end
    end

    # Fallback to keyword search (same as CreativeRoutineGenerator#keyword_search)
    actual_type = force_keyword ? "keyword" : "keyword (fallback)"
    keywords = query.split(/\s+/).reject { |w| w.length < 2 }

    scope = FitnessKnowledgeChunk
      .where(knowledge_type: knowledge_type)
      .for_user_level(user_level)
      .includes(:youtube_video)

    # Filter by target muscles for exercise_technique (same as generator)
    if target_muscles.any? && knowledge_type == "exercise_technique"
      muscle_conditions = target_muscles.map { "muscle_group ILIKE ? OR exercise_name ILIKE ? OR content ILIKE ?" }
      muscle_values = target_muscles.flat_map { |m| ["%#{m}%", "%#{m}%", "%#{m}%"] }
      scope = scope.where(muscle_conditions.join(" OR "), *muscle_values)
    end

    # Search by keywords in content/summary
    if keywords.any?
      keyword_conditions = keywords.map { "content ILIKE ? OR summary ILIKE ?" }
      keyword_values = keywords.flat_map { |kw| ["%#{kw}%", "%#{kw}%"] }
      scope = scope.where(keyword_conditions.join(" OR "), *keyword_values)
    end

    chunks = scope.order(Arel.sql("RANDOM()")).limit(limit)

    results = chunks.map do |c|
      {
        id: c.id,
        knowledge_type: c.knowledge_type,
        difficulty_level: c.difficulty_level,
        exercise_name: c.exercise_name,
        muscle_group: c.muscle_group,
        summary: c.summary,
        content: c.content,
        has_embedding: embedding_column_exists && c.embedding.present?,
        similarity_score: nil,
        video_title: c.youtube_video&.title,
        channel_name: c.youtube_video&.youtube_channel&.name
      }
    end

    [results, actual_type]
  end

  # Translate Korean fitness query to English for better embedding search
  def translate_query_for_embedding(query)
    return query if query.match?(/\A[a-zA-Z0-9\s]+\z/) # Already English

    system_prompt = "You are a fitness query translator. Translate the Korean fitness query to English. Keep it concise and focused on fitness terms. Only output the English translation, nothing else."

    result = AiTrainer::LlmGateway.chat(
      prompt: query,
      task: :query_translation,
      system: system_prompt,
      cache_system: false
    )

    if result[:success] && result[:content].present?
      translated = result[:content].strip
      Rails.logger.info("[Search] Translated '#{query}' -> '#{translated}'")
      translated
    else
      Rails.logger.warn("[Search] Translation failed, using original query")
      query
    end
  rescue StandardError => e
    Rails.logger.error("[Search] Translation error: #{e.message}")
    query
  end

  # Same logic as CreativeRoutineGenerator#extract_target_muscles
  def extract_target_muscles_from_query(query)
    # Map Korean keywords to English muscle_group values (matching DB)
    muscle_keywords = {
      "back" => %w[등 back 광배 승모 lat],
      "chest" => %w[가슴 chest 흉근 대흉근 pec],
      "shoulders" => %w[어깨 shoulder 삼각근 deltoid],
      "arms" => %w[팔 arm 이두 삼두 bicep tricep],
      "legs" => %w[하체 leg 다리 허벅지 대퇴 quadricep hamstring],
      "core" => %w[코어 core 복근 abs 복부],
      "full_body" => %w[전신 full body 전체]
    }

    query_lower = query.downcase
    matched_muscles = []

    muscle_keywords.each do |muscle_en, keywords|
      matched_muscles << muscle_en if keywords.any? { |kw| query_lower.include?(kw) }
    end

    matched_muscles
  end

  # Legacy method - kept for compatibility
  def perform_search_with_type(query:, search_type:, knowledge_type:, limit:)
    scope = if knowledge_type == "all"
              FitnessKnowledgeChunk.all
            else
              FitnessKnowledgeChunk.where(knowledge_type: knowledge_type)
            end

    chunks, actual_type = case search_type
    when "semantic"
      [semantic_search(query, scope, limit), @actual_search_type || "semantic"]
    when "keyword"
      [keyword_search(query, scope, limit), "keyword"]
    when "hybrid"
      [hybrid_search(query, scope, limit), "hybrid"]
    else
      [semantic_search(query, scope, limit), @actual_search_type || "semantic"]
    end

    results = chunks.map do |chunk|
      {
        id: chunk.id,
        type: chunk.knowledge_type,
        difficulty: chunk.difficulty_level,
        exercise_name: chunk.exercise_name,
        muscle_group: chunk.muscle_group,
        summary: chunk.summary,
        content: chunk.content&.truncate(500),
        has_embedding: chunk.embedding.present?,
        similarity_score: chunk.respond_to?(:neighbor_distance) ? (1 - chunk.neighbor_distance).round(4) : nil,
        source: {
          video_title: chunk.youtube_video&.title,
          channel: chunk.youtube_video&.youtube_channel&.name
        }
      }
    end

    [results, actual_type]
  end

  def semantic_search(query, scope, limit)
    # Check if embedding column exists
    unless FitnessKnowledgeChunk.column_names.include?("embedding")
      Rails.logger.warn("Embedding column does not exist, falling back to keyword")
      @actual_search_type = "keyword (no embedding column)"
      return keyword_search(query, scope, limit)
    end

    unless EmbeddingService.pgvector_available? && EmbeddingService.configured?
      Rails.logger.warn("Semantic search unavailable, falling back to keyword")
      @actual_search_type = "keyword (pgvector/gemini unavailable)"
      return keyword_search(query, scope, limit)
    end

    # Check if there are any chunks with embeddings
    chunks_with_embeddings = scope.where.not(embedding: nil).count
    if chunks_with_embeddings == 0
      Rails.logger.warn("No chunks with embeddings found, falling back to keyword")
      @actual_search_type = "keyword (no embeddings)"
      return keyword_search(query, scope, limit)
    end

    query_embedding = EmbeddingService.generate_query_embedding(query)
    unless query_embedding.present?
      Rails.logger.warn("Failed to generate query embedding, falling back to keyword")
      @actual_search_type = "keyword (embedding failed)"
      return keyword_search(query, scope, limit)
    end

    @actual_search_type = "semantic"
    results = scope.where.not(embedding: nil)
                   .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
                   .limit(limit)

    # If semantic search returns no results, try keyword fallback
    if results.empty?
      Rails.logger.warn("Semantic search returned no results, falling back to keyword")
      @actual_search_type = "keyword (no semantic matches)"
      return keyword_search(query, scope, limit)
    end

    results
  end

  def keyword_search(query, scope, limit)
    # Extract keywords from query
    keywords = query.downcase.split(/[\s,]+/).reject { |w| w.length < 2 }

    return scope.limit(limit) if keywords.empty?

    # Build search conditions
    conditions = keywords.map do |keyword|
      sanitized = ActiveRecord::Base.sanitize_sql_like(keyword)
      "(LOWER(content) LIKE '%#{sanitized}%' OR LOWER(summary) LIKE '%#{sanitized}%' OR LOWER(exercise_name) LIKE '%#{sanitized}%')"
    end

    scope.where(conditions.join(" OR "))
         .order(Arel.sql("CASE WHEN LOWER(summary) LIKE '%#{ActiveRecord::Base.sanitize_sql_like(keywords.first)}%' THEN 0 ELSE 1 END"))
         .limit(limit)
  end

  def hybrid_search(query, scope, limit)
    # Combine semantic and keyword results
    semantic_results = semantic_search(query, scope, limit / 2)
    keyword_results = keyword_search(query, scope, limit / 2)

    # Merge and dedupe, prioritizing semantic results
    seen_ids = Set.new
    combined = []

    semantic_results.each do |chunk|
      next if seen_ids.include?(chunk.id)
      seen_ids.add(chunk.id)
      combined << chunk
    end

    keyword_results.each do |chunk|
      next if seen_ids.include?(chunk.id)
      seen_ids.add(chunk.id)
      combined << chunk
      break if combined.size >= limit
    end

    combined.first(limit)
  end

  def verify_admin_token
    token = request.headers["X-Admin-Token"] || params[:admin_token]
    expected = ENV["ADMIN_SECRET_TOKEN"]

    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
