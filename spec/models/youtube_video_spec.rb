# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeVideo, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:youtube_channel) }
    it { is_expected.to have_many(:fitness_knowledge_chunks).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:youtube_video) }

    it { is_expected.to validate_presence_of(:video_id) }
    it { is_expected.to validate_uniqueness_of(:video_id) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:analysis_status) }
    it { is_expected.to validate_inclusion_of(:analysis_status).in_array(YoutubeVideo::STATUSES) }
  end

  describe "scopes" do
    let!(:pending_video) { create(:youtube_video, :pending) }
    let!(:analyzing_video) { create(:youtube_video, :analyzing) }
    let!(:completed_video) { create(:youtube_video, :completed) }
    let!(:failed_video) { create(:youtube_video, :failed) }

    describe ".pending" do
      it "returns pending videos" do
        expect(described_class.pending).to contain_exactly(pending_video)
      end
    end

    describe ".analyzing" do
      it "returns analyzing videos" do
        expect(described_class.analyzing).to contain_exactly(analyzing_video)
      end
    end

    describe ".completed" do
      it "returns completed videos" do
        expect(described_class.completed).to contain_exactly(completed_video)
      end
    end

    describe ".failed" do
      it "returns failed videos" do
        expect(described_class.failed).to contain_exactly(failed_video)
      end
    end

    describe ".published_after" do
      let!(:recent_video) { create(:youtube_video, published_at: 1.day.ago) }
      let!(:old_video) { create(:youtube_video, published_at: 1.year.ago) }

      it "returns videos published after the given date" do
        result = described_class.published_after(1.month.ago)
        expect(result).to include(recent_video)
        expect(result).not_to include(old_video)
      end
    end
  end

  describe "#start_analysis!" do
    let(:video) { create(:youtube_video, :pending) }

    it "updates status to analyzing" do
      video.start_analysis!
      expect(video.analysis_status).to eq("analyzing")
    end
  end

  describe "#complete_analysis!" do
    let(:video) { create(:youtube_video, :analyzing) }
    let(:result) do
      {
        category: "strength",
        difficulty_level: "advanced",
        language: "ko"
      }
    end

    it "updates status and stores results" do
      video.complete_analysis!(result)

      expect(video.analysis_status).to eq("completed")
      expect(video.analyzed_at).to be_present
      expect(video.category).to eq("strength")
      expect(video.difficulty_level).to eq("advanced")
    end
  end

  describe "#fail_analysis!" do
    let(:video) { create(:youtube_video, :analyzing) }

    it "updates status and stores error" do
      video.fail_analysis!("API error")

      expect(video.analysis_status).to eq("failed")
      expect(video.analysis_error).to eq("API error")
    end
  end

  describe "#youtube_url" do
    let(:video) { build(:youtube_video, video_id: "abc123") }

    it "returns the YouTube URL" do
      expect(video.youtube_url).to eq("https://www.youtube.com/watch?v=abc123")
    end
  end

  describe "#duration_formatted" do
    it "formats duration correctly" do
      video = build(:youtube_video, duration_seconds: 185)
      expect(video.duration_formatted).to eq("3:05")
    end

    it "returns nil when duration is nil" do
      video = build(:youtube_video, duration_seconds: nil)
      expect(video.duration_formatted).to be_nil
    end
  end
end
