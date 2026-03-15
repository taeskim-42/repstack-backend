# frozen_string_literal: true

module Types
  class ExerciseVideoClipType < Types::BaseObject
    description "Exercise-specific video clip with accurate timestamps"

    field :id, ID, null: false
    field :exercise_name, String, null: false
    field :clip_type, String, null: false
    field :title, String, null: false
    field :summary, String, null: true
    field :video_url, String, null: false
    field :video_id, String, null: false
    field :channel_name, String, null: false
    field :timestamp_start, Float, null: false
    field :timestamp_end, Float, null: false
    field :source_language, String, null: false

    def video_url
      object.video_url_with_timestamp
    end

    def video_id
      object.youtube_video.video_id
    end

    def channel_name
      object.youtube_video.youtube_channel&.name || "Unknown"
    end
  end
end
