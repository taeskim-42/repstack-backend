# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeChannel, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:youtube_videos).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:youtube_channel) }

    it { is_expected.to validate_presence_of(:channel_id) }
    it { is_expected.to validate_uniqueness_of(:channel_id) }
    it { is_expected.to validate_presence_of(:handle) }
    it { is_expected.to validate_uniqueness_of(:handle) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }
  end

  describe "scopes" do
    let!(:active_channel) { create(:youtube_channel, active: true) }
    let!(:inactive_channel) { create(:youtube_channel, :inactive) }
    let!(:needs_sync_channel) { create(:youtube_channel, :needs_sync) }
    let!(:synced_channel) { create(:youtube_channel, :synced) }

    describe ".active" do
      it "returns only active channels" do
        expect(described_class.active).to include(active_channel)
        expect(described_class.active).not_to include(inactive_channel)
      end
    end

    describe ".needs_sync" do
      it "returns channels that need syncing" do
        expect(described_class.needs_sync).to include(active_channel)
        expect(described_class.needs_sync).to include(needs_sync_channel)
        expect(described_class.needs_sync).not_to include(synced_channel)
        expect(described_class.needs_sync).not_to include(inactive_channel)
      end
    end
  end

  describe "#mark_synced!" do
    let(:channel) { create(:youtube_channel) }

    it "updates last_synced_at" do
      channel.mark_synced!
      expect(channel.last_synced_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#mark_analyzed!" do
    let(:channel) { create(:youtube_channel) }

    it "updates last_analyzed_at" do
      channel.mark_analyzed!
      expect(channel.last_analyzed_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#pending_videos" do
    let(:channel) { create(:youtube_channel) }
    let!(:pending_video) { create(:youtube_video, youtube_channel: channel, analysis_status: "pending") }
    let!(:completed_video) { create(:youtube_video, :completed, youtube_channel: channel) }

    it "returns only pending videos" do
      expect(channel.pending_videos).to contain_exactly(pending_video)
    end
  end

  describe ".seed_configured_channels!" do
    it "creates channels from config" do
      expect {
        described_class.seed_configured_channels!
      }.to change(described_class, :count).by(YoutubeConfig::CHANNELS.count)
    end

    it "is idempotent" do
      described_class.seed_configured_channels!
      expect {
        described_class.seed_configured_channels!
      }.not_to change(described_class, :count)
    end
  end
end
