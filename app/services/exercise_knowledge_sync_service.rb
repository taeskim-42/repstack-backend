# frozen_string_literal: true

# Syncs knowledge chunks to Exercise table
# - Matches chunk exercise_name to Exercise records
# - Populates video_references, description, form_tips, common_mistakes
class ExerciseKnowledgeSyncService
  include AiTrainer::ExerciseNameNormalizer

  # Patterns that indicate non-exercise content
  NON_EXERCISE_PATTERNS = [
    /^N\/A$/i,
    /protocol$/i,
    /strategy$/i,
    /schedule$/i,
    /tracking$/i,
    /monitoring$/i,
    /intake$/i,
    /consumption$/i,
    /storage$/i,
    /injection$/i,
    /treatment$/i,
    /preparation$/i,
    /management$/i,
    /methodology$/i,
    /psychology$/i,
    /mindset$/i,
    /motivation$/i,
    /lifestyle$/i,
    /content_/i,
    /social_/i,
    /mental_/i,
    /medical_/i,
    /genetic_/i,
    /^all_exercises$/i,
    /_avoidance$/i,
    /_evasion$/i,
    /side_effects$/i,
    /cycle$/i,
    /phase$/i,
    /testing$/i,
    /analysis$/i
  ].freeze

  def initialize(dry_run: true)
    @dry_run = dry_run
    @stats = {
      chunks_processed: 0,
      exercises_matched: 0,
      exercises_updated: 0,
      video_refs_added: 0,
      skipped_non_exercise: 0,
      skipped_no_match: 0
    }
    @exercise_cache = build_exercise_cache
  end

  def sync_all
    Rails.logger.info "[ExerciseKnowledgeSync] Starting sync (dry_run: #{@dry_run})"

    # Group chunks by exercise_name for efficiency
    chunk_groups = FitnessKnowledgeChunk
      .where.not(exercise_name: [nil, ""])
      .includes(:youtube_video)
      .group_by(&:exercise_name)

    chunk_groups.each do |exercise_name, chunks|
      process_exercise_chunks(exercise_name, chunks)
    end

    log_stats
    @stats
  end

  def sync_exercise(exercise_name)
    chunks = FitnessKnowledgeChunk
      .where(exercise_name: exercise_name)
      .includes(:youtube_video)

    return nil if chunks.empty?

    process_exercise_chunks(exercise_name, chunks.to_a)
  end

  private

  def build_exercise_cache
    cache = {}
    Exercise.find_each do |exercise|
      # Index by multiple possible names
      [exercise.display_name, exercise.name, exercise.english_name].compact.each do |name|
        normalized = normalize_key(name)
        cache[normalized] = exercise
      end
    end
    cache
  end

  def normalize_key(name)
    name.to_s.downcase.strip.gsub(/[_\-\s]+/, "_")
  end

  def process_exercise_chunks(exercise_name, chunks)
    @stats[:chunks_processed] += chunks.size

    # Skip non-exercise content
    if non_exercise?(exercise_name)
      @stats[:skipped_non_exercise] += chunks.size
      return
    end

    # Handle compound names (e.g., "bench_press, squat")
    individual_names = split_compound_name(exercise_name)

    individual_names.each do |name|
      exercise = find_matching_exercise(name)

      if exercise.nil?
        @stats[:skipped_no_match] += 1
        next
      end

      @stats[:exercises_matched] += 1
      update_exercise_from_chunks(exercise, chunks)
    end
  end

  def non_exercise?(name)
    NON_EXERCISE_PATTERNS.any? { |pattern| name.match?(pattern) }
  end

  def split_compound_name(name)
    # Split by comma or "and"
    name.split(/,\s*|\s+and\s+/).map(&:strip).reject(&:empty?)
  end

  def find_matching_exercise(name)
    normalized = normalize_key(name)

    # Direct match
    return @exercise_cache[normalized] if @exercise_cache[normalized]

    # Try Korean normalization
    korean_name = AiTrainer::ExerciseNameNormalizer.normalize(name.gsub("_", " "))
    korean_normalized = normalize_key(korean_name)
    return @exercise_cache[korean_normalized] if @exercise_cache[korean_normalized]

    # Fuzzy match - check if name is contained in any exercise name
    @exercise_cache.each do |key, exercise|
      return exercise if key.include?(normalized) || normalized.include?(key)
    end

    nil
  end

  def update_exercise_from_chunks(exercise, chunks)
    updates = {}

    # Aggregate video references
    video_refs = build_video_references(chunks)
    if video_refs.any?
      existing_refs = exercise.video_references || []
      new_refs = merge_video_references(existing_refs, video_refs)
      updates[:video_references] = new_refs if new_refs != existing_refs
      @stats[:video_refs_added] += (new_refs.size - existing_refs.size)
    end

    # Aggregate descriptions from exercise_technique chunks
    technique_chunks = chunks.select { |c| c.knowledge_type == "exercise_technique" }
    if technique_chunks.any? && exercise.description.blank?
      updates[:description] = aggregate_summaries(technique_chunks, max_length: 500)
    end

    # Aggregate form tips from form_check chunks
    form_chunks = chunks.select { |c| c.knowledge_type == "form_check" }
    if form_chunks.any? && exercise.form_tips.blank?
      updates[:form_tips] = aggregate_summaries(form_chunks, max_length: 500)
    end

    return if updates.empty?

    if @dry_run
      Rails.logger.info "[ExerciseKnowledgeSync] Would update #{exercise.display_name}: #{updates.keys.join(', ')}"
    else
      exercise.update!(updates)
      @stats[:exercises_updated] += 1
      Rails.logger.info "[ExerciseKnowledgeSync] Updated #{exercise.display_name}: #{updates.keys.join(', ')}"
    end
  end

  def build_video_references(chunks)
    chunks.filter_map do |chunk|
      video = chunk.youtube_video
      next unless video

      {
        "video_id" => video.video_id,
        "title" => video.title,
        "url" => "https://www.youtube.com/watch?v=#{video.video_id}",
        "timestamp_start" => chunk.timestamp_start,
        "timestamp_end" => chunk.timestamp_end,
        "summary" => chunk.summary&.truncate(200),
        "knowledge_type" => chunk.knowledge_type
      }
    end.uniq { |ref| [ref["video_id"], ref["timestamp_start"]] }
  end

  def merge_video_references(existing, new_refs)
    existing_keys = existing.map { |r| [r["video_id"], r["timestamp_start"]] }.to_set

    merged = existing.dup
    new_refs.each do |ref|
      key = [ref["video_id"], ref["timestamp_start"]]
      merged << ref unless existing_keys.include?(key)
    end

    merged
  end

  def aggregate_summaries(chunks, max_length: 500)
    summaries = chunks.map(&:summary).compact.uniq
    combined = summaries.join("\n\n")
    combined.truncate(max_length)
  end

  def log_stats
    Rails.logger.info "[ExerciseKnowledgeSync] Completed:"
    Rails.logger.info "  - Chunks processed: #{@stats[:chunks_processed]}"
    Rails.logger.info "  - Exercises matched: #{@stats[:exercises_matched]}"
    Rails.logger.info "  - Exercises updated: #{@stats[:exercises_updated]}"
    Rails.logger.info "  - Video refs added: #{@stats[:video_refs_added]}"
    Rails.logger.info "  - Skipped (non-exercise): #{@stats[:skipped_non_exercise]}"
    Rails.logger.info "  - Skipped (no match): #{@stats[:skipped_no_match]}"
  end
end
