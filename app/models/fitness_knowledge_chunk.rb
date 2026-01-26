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

  # Scopes
  scope :exercise_techniques, -> { where(knowledge_type: "exercise_technique") }
  scope :routine_designs, -> { where(knowledge_type: "routine_design") }
  scope :nutrition_recovery, -> { where(knowledge_type: "nutrition_recovery") }
  scope :form_checks, -> { where(knowledge_type: "form_check") }
  scope :for_exercise, ->(name) {
    where("exercise_name ILIKE :q OR content ILIKE :q OR summary ILIKE :q", q: "%#{name}%")
  }
  scope :for_muscle_group, ->(group) {
    where("muscle_group ILIKE :q OR content ILIKE :q", q: "%#{group}%")
  }
  scope :with_embedding, -> { where.not(embedding: nil) }

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

      # Search in exercise_name, content, and summary fields
      if exercise_names.present?
        exercise_conditions = exercise_names.map { |_| "(exercise_name ILIKE ? OR content ILIKE ? OR summary ILIKE ?)" }
        exercise_values = exercise_names.flat_map { |n| ["%#{n}%", "%#{n}%", "%#{n}%"] }
        scope = scope.where(exercise_conditions.join(" OR "), *exercise_values)
      end

      # Search in muscle_group and content fields
      if muscle_groups.present?
        muscle_conditions = muscle_groups.map { |_| "(muscle_group ILIKE ? OR content ILIKE ?)" }
        muscle_values = muscle_groups.flat_map { |g| ["%#{g}%", "%#{g}%"] }
        scope = scope.where(muscle_conditions.join(" OR "), *muscle_values)
      end

      scope = scope.where(knowledge_type: knowledge_types) if knowledge_types.present?

      scope.limit(limit)
    end
  end

  # Instance methods
  def video_timestamp_url
    return youtube_video.youtube_url unless timestamp_start

    "#{youtube_video.youtube_url}&t=#{timestamp_start}"
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
