# frozen_string_literal: true

class ExerciseVideoClip < ApplicationRecord
  belongs_to :youtube_video
  belongs_to :exercise, optional: true

  CLIP_TYPES = %w[technique form_check pro_tip common_mistake].freeze

  validates :exercise_name, presence: true
  validates :clip_type, presence: true, inclusion: { in: CLIP_TYPES }
  validates :title, presence: true
  validates :content, presence: true
  validates :timestamp_start, presence: true
  validates :timestamp_end, presence: true

  # Scopes
  scope :for_exercise, ->(name) { where(exercise_name: name) }
  scope :for_locale, ->(locale) { where(source_language: locale) }
  scope :techniques, -> { where(clip_type: "technique") }
  scope :form_checks, -> { where(clip_type: "form_check") }
  scope :pro_tips, -> { where(clip_type: "pro_tip") }
  scope :common_mistakes, -> { where(clip_type: "common_mistake") }

  def technique?
    clip_type == "technique"
  end

  def form_check?
    clip_type == "form_check"
  end

  def pro_tip?
    clip_type == "pro_tip"
  end

  def common_mistake?
    clip_type == "common_mistake"
  end

  def video_url_with_timestamp
    start_seconds = timestamp_start.to_i
    "https://www.youtube.com/watch?v=#{youtube_video.video_id}&t=#{start_seconds}"
  end

  def video_id
    youtube_video.video_id
  end

  def channel_name
    youtube_video.youtube_channel&.name
  end
end
