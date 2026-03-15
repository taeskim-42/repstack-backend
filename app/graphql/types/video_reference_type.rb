# frozen_string_literal: true

module Types
  class VideoReferenceType < Types::BaseObject
    description "Reference to a YouTube video source"

    field :video_id, String, null: true, description: "YouTube video ID"
    field :title, String, null: true, description: "Video title"
    field :url, String, null: true, description: "YouTube video URL"
    field :timestamp_start, Integer, null: true, description: "Start timestamp in seconds"
    field :chunk_id, ID, null: true, description: "Related FitnessKnowledgeChunk ID"
    field :timestamp_end, Float, null: true, description: "End timestamp in seconds"
    field :clip_type, String, null: true, description: "Clip type: technique, form_check, pro_tip, common_mistake"
    field :channel_name, String, null: true, description: "YouTube channel name"
    field :summary, String, null: true, description: "One-line summary of the clip"

    # Hash key is :channel (not :channel_name) in format_clip_reference output
    def channel_name
      object.is_a?(Hash) ? (object[:channel] || object["channel"]) : nil
    end
  end
end
