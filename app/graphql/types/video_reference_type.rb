# frozen_string_literal: true

module Types
  class VideoReferenceType < Types::BaseObject
    description "Reference to a YouTube video source"

    field :video_id, String, null: true, description: "YouTube video ID"
    field :title, String, null: true, description: "Video title"
    field :url, String, null: true, description: "YouTube video URL"
    field :timestamp_start, Integer, null: true, description: "Start timestamp in seconds"
    field :chunk_id, ID, null: true, description: "Related FitnessKnowledgeChunk ID"
  end
end
