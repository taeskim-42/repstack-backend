# frozen_string_literal: true

FactoryBot.define do
  factory :youtube_channel do
    sequence(:channel_id) { |n| "UCchannel#{n}" }
    sequence(:handle) { |n| "channel_handle_#{n}" }
    sequence(:name) { |n| "Fitness Channel #{n}" }
    url { "https://www.youtube.com/@#{handle}" }
    description { "A fitness channel focused on strength training" }
    thumbnail_url { "https://example.com/thumbnail.jpg" }
    subscriber_count { rand(1000..1_000_000) }
    video_count { rand(10..500) }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :synced do
      last_synced_at { 1.hour.ago }
    end

    trait :analyzed do
      last_synced_at { 1.hour.ago }
      last_analyzed_at { 30.minutes.ago }
    end

    trait :needs_sync do
      last_synced_at { 2.days.ago }
    end

    trait :superbeast do
      channel_id { "superbeast1004" }
      handle { "superbeast1004" }
      name { "SuperBeast" }
      url { "https://www.youtube.com/@superbeast1004" }
    end
  end
end
