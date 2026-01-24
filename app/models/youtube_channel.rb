# frozen_string_literal: true

class YoutubeChannel < ApplicationRecord
  has_many :youtube_videos, dependent: :destroy

  # Validations
  validates :channel_id, presence: true, uniqueness: true
  validates :handle, presence: true, uniqueness: true
  validates :name, presence: true
  validates :url, presence: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :needs_sync, -> { active.where(last_synced_at: nil).or(active.where("last_synced_at < ?", 1.day.ago)) }

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
        find_or_create_by!(handle: config[:handle]) do |channel|
          channel.channel_id = config[:handle] # Will be updated when synced
          channel.name = config[:name]
          channel.url = config[:url]
        end
      end
    end
  end
end
