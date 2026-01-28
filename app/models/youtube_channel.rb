# frozen_string_literal: true

class YoutubeChannel < ApplicationRecord
  has_many :youtube_videos, dependent: :destroy

  # Validations
  validates :channel_id, presence: true, uniqueness: true
  validates :handle, presence: true, uniqueness: true
  validates :name, presence: true
  validates :url, presence: true
  validates :language, presence: true, inclusion: { in: %w[ko en] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :needs_sync, -> { active.where(last_synced_at: nil).or(active.where("last_synced_at < ?", 1.day.ago)) }
  scope :korean, -> { where(language: "ko") }
  scope :english, -> { where(language: "en") }

  # Instance methods
  def mark_synced!
    update!(last_synced_at: Time.current)
  end

  def mark_analyzed!
    update!(last_analyzed_at: Time.current)
  end

  def pending_videos
    youtube_videos.where(analysis_status: "pending")
  end

  def analyzed_videos
    youtube_videos.where(analysis_status: "completed")
  end

  # Class methods for seeding configured channels
  class << self
    def seed_configured_channels!
      YoutubeConfig::CHANNELS.each do |config|
        channel = find_or_initialize_by(handle: config[:handle])
        channel.channel_id = config[:handle] # Will be updated when synced
        channel.name = config[:name]
        channel.url = config[:url]
        channel.language = config[:language] || "ko"
        channel.save!
      end
    end
  end
end
