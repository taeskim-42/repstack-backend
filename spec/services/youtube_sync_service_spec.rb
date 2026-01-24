# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeSyncService do
  let(:channel) { create(:youtube_channel, handle: "test_channel", url: "https://www.youtube.com/@test_channel") }

  describe ".sync_channel" do
    let(:mock_video_data) do
      [
        { video_id: "vid001", title: "Test Video 1", upload_date: 1.day.ago.to_date },
        { video_id: "vid002", title: "Test Video 2", upload_date: 2.days.ago.to_date }
      ]
    end

    before do
      allow(YoutubeChannelScraper).to receive(:extract_video_metadata).and_return(mock_video_data)
    end

    it "creates videos from yt-dlp output" do
      expect {
        described_class.sync_channel(channel)
      }.to change(YoutubeVideo, :count).by(2)
    end

    it "marks channel as synced" do
      described_class.sync_channel(channel)
      expect(channel.reload.last_synced_at).to be_within(1.minute).of(Time.current)
    end

    it "returns video count" do
      count = described_class.sync_channel(channel)
      expect(count).to eq(2)
    end

    it "is idempotent - doesn't duplicate videos" do
      described_class.sync_channel(channel)

      expect {
        described_class.sync_channel(channel)
      }.not_to change(YoutubeVideo, :count)
    end

    context "when yt-dlp is not installed" do
      before do
        allow(YoutubeChannelScraper).to receive(:extract_video_metadata)
          .and_raise(YoutubeChannelScraper::YtDlpNotFoundError, "yt-dlp not installed")
      end

      it "raises an error" do
        expect { described_class.sync_channel(channel) }
          .to raise_error(YoutubeChannelScraper::YtDlpNotFoundError)
      end
    end
  end

  describe ".sync_all_channels" do
    let!(:active_channel1) { create(:youtube_channel, active: true) }
    let!(:active_channel2) { create(:youtube_channel, active: true) }
    let!(:inactive_channel) { create(:youtube_channel, active: false) }

    before do
      allow(YoutubeChannelScraper).to receive(:extract_video_metadata).and_return([])
    end

    it "syncs all active channels" do
      described_class.sync_all_channels

      expect(active_channel1.reload.last_synced_at).to be_present
      expect(active_channel2.reload.last_synced_at).to be_present
      expect(inactive_channel.reload.last_synced_at).to be_nil
    end
  end

  describe ".sync_new_videos_only" do
    before do
      channel.update!(last_synced_at: 2.days.ago)
      allow(YoutubeChannelScraper).to receive(:extract_new_videos).and_return([
        { video_id: "new_vid", title: "New Video", upload_date: 1.hour.ago.to_date }
      ])
    end

    it "only fetches videos since last sync" do
      new_count = described_class.sync_new_videos_only(channel)

      expect(new_count).to eq(1)
      expect(YoutubeVideo.find_by(video_id: "new_vid")).to be_present
    end
  end
end
