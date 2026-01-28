# frozen_string_literal: true

class FitnessKnowledgeChunk < ApplicationRecord
  belongs_to :youtube_video

  # Knowledge types
  KNOWLEDGE_TYPES = %w[
    exercise_technique
    routine_design
    nutrition_recovery
    form_check
  ].freeze

  # Validations
  validates :knowledge_type, presence: true, inclusion: { in: KNOWLEDGE_TYPES }
  validates :content, presence: true
  validates :language, presence: true, inclusion: { in: %w[ko en] }

  # Scopes
  scope :exercise_techniques, -> { where(knowledge_type: "exercise_technique") }
  scope :routine_designs, -> { where(knowledge_type: "routine_design") }
  scope :nutrition_recovery, -> { where(knowledge_type: "nutrition_recovery") }
  scope :form_checks, -> { where(knowledge_type: "form_check") }
  scope :korean, -> { where(language: "ko") }
  scope :english, -> { where(language: "en") }
  scope :with_original, -> { where.not(content_original: nil) }
  # Exact match for exercise name (handles comma-separated values)
  scope :for_exercise, ->(name) {
    where("? = ANY(string_to_array(exercise_name, ', ')) OR exercise_name = ?", name, name)
  }
  # Fuzzy match for exercise (includes content/summary search)
  scope :for_exercise_fuzzy, ->(name) {
    where("exercise_name ILIKE :q OR content ILIKE :q OR summary ILIKE :q", q: "%#{name}%")
  }
  scope :for_muscle_group, ->(group) {
    where("muscle_group ILIKE :q OR content ILIKE :q", q: "%#{group}%")
  }
  scope :with_embedding, -> { where.not(embedding: nil) }

  # Difficulty level scopes
  DIFFICULTY_LEVELS = %w[beginner intermediate advanced all].freeze
  scope :for_level, ->(level) {
    case level.to_s
    when "beginner"
      where(difficulty_level: %w[beginner all])
    when "intermediate"
      where(difficulty_level: %w[intermediate all])
    when "advanced"
      where(difficulty_level: %w[advanced all])
    else
      all
    end
  }
  scope :for_user_level, ->(numeric_level) {
    tier = case numeric_level
           when 1..2 then "beginner"
           when 3..5 then "intermediate"
           else "advanced"
           end
    for_level(tier)
  }

  # Enable neighbor gem for vector search (only if pgvector is available)
  if column_names.include?("embedding")
    has_neighbors :embedding
  end

  # Class methods for RAG search
  class << self
    # Search by semantic similarity using vector embeddings
    def semantic_search(query_embedding, limit: 5)
      return [] unless respond_to?(:nearest_neighbors)

      nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(limit)
    end

    # Fallback keyword search when pgvector is not available
    def keyword_search(query, limit: 10)
      where("content ILIKE :query OR summary ILIKE :query OR exercise_name ILIKE :query",
        query: "%#{query}%")
        .limit(limit)
    end

    # Combined search - uses vector if available, falls back to keyword
    def search(query, embedding: nil, limit: 5)
      if embedding.present? && column_names.include?("embedding")
        semantic_search(embedding, limit: limit)
      else
        keyword_search(query, limit: limit)
      end
    end

    # Get knowledge relevant to a user's context
    def relevant_for_context(exercise_names: [], muscle_groups: [], knowledge_types: nil, limit: 10)
      scope = all

      # Exact match for exercise names (handles comma-separated values in exercise_name column)
      if exercise_names.present?
        exercise_conditions = exercise_names.map { |_| "(? = ANY(string_to_array(exercise_name, ', ')) OR exercise_name = ?)" }
        exercise_values = exercise_names.flat_map { |n| [n, n] }
        scope = scope.where(exercise_conditions.join(" OR "), *exercise_values)
      end

      # Search in muscle_group and content fields
      if muscle_groups.present?
        muscle_conditions = muscle_groups.map { |_| "(muscle_group ILIKE ? OR content ILIKE ?)" }
        muscle_values = muscle_groups.flat_map { |g| ["%#{g}%", "%#{g}%"] }
        scope = scope.where(muscle_conditions.join(" OR "), *muscle_values)
      end

      scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?

      # Random order so different videos appear each time
      scope.order("RANDOM()").limit(limit)
    end
  end

  # Instance methods
  def video_timestamp_url
    # Return URL with timestamp if available
    return youtube_video.youtube_url unless timestamp_start && timestamp_start > 0

    url = youtube_video.youtube_url
    # Handle different YouTube URL formats
    if url.include?("?")
      "#{url}&t=#{timestamp_start}"
    else
      "#{url}?t=#{timestamp_start}"
    end

    url = youtube_video.youtube_url
    # Handle different YouTube URL formats
    if url.include?("?")
      # URL already has query params (e.g., youtube.com/watch?v=xxx)
      "#{url}&t=#{timestamp_start}"
    else
      # URL without query params (e.g., youtu.be/xxx)
      "#{url}?t=#{timestamp_start}"
    end
  end

  def source_reference
    {
      video_title: youtube_video.title,
      video_url: video_timestamp_url,
      channel_name: youtube_video.youtube_channel.name,
      timestamp: timestamp_start
    }
  end
end
