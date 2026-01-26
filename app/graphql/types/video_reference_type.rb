# frozen_string_literal: true

module Types
  class VideoReferenceType < Types::BaseObject
    description "Reference to a YouTube video source"

    field :title, String, null: true, description: "Video title"
    field :url, String, null: true, description: "YouTube video URL"
  end
end
