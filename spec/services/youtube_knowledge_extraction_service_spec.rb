# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeKnowledgeExtractionService do
  let(:channel) { create(:youtube_channel) }
  let(:video) { create(:youtube_video, youtube_channel: channel) }

  describe ".analyze_video" do
    context "when Gemini is not configured" do
      before do
        allow(GeminiConfig).to receive(:configured?).and_return(false)
      end

      it "raises an error" do
        expect { described_class.analyze_video(video) }.to raise_error("Gemini API not configured")
      end
    end

    context "when Gemini is configured" do
      let(:gemini_response) do
        {
          category: "strength",
          difficulty_level: "intermediate",
          language: "ko",
          knowledge_chunks: [
            {
              type: "exercise_technique",
              content: "벤치프레스는 가슴 운동의 핵심입니다. 바를 내릴 때 가슴 중앙에 닿도록 하세요.",
              summary: "벤치프레스 자세",
              exercise_name: "bench_press",
              muscle_group: "chest",
              difficulty_level: "intermediate"
            },
            {
              type: "form_check",
              content: "견갑골을 모아 안정적인 자세를 만드세요. 어깨가 앞으로 나오면 부상 위험이 있습니다.",
              summary: "견갑골 위치",
              exercise_name: "bench_press",
              muscle_group: "chest"
            }
          ]
        }
      end

      before do
        allow(GeminiConfig).to receive(:configured?).and_return(true)
        allow(GeminiConfig).to receive(:generate_content).and_return(gemini_response.to_json)
      end

      it "updates video status to analyzing then completed" do
        expect(video.analysis_status).to eq("pending")

        described_class.analyze_video(video)

        expect(video.reload.analysis_status).to eq("completed")
      end

      it "creates knowledge chunks from the response" do
        expect {
          described_class.analyze_video(video)
        }.to change(FitnessKnowledgeChunk, :count).by(2)
      end

      it "stores the raw analysis result" do
        described_class.analyze_video(video)

        expect(video.reload.raw_analysis).to include("category" => "strength")
      end

      it "sets video category and difficulty" do
        described_class.analyze_video(video)

        video.reload
        expect(video.category).to eq("strength")
        expect(video.difficulty_level).to eq("intermediate")
      end
    end

    context "when video is already analyzed" do
      let(:video) { create(:youtube_video, :completed, youtube_channel: channel) }

      it "skips analysis" do
        expect(GeminiConfig).not_to receive(:generate_content)
        described_class.analyze_video(video)
      end
    end

    context "when analysis fails" do
      before do
        allow(GeminiConfig).to receive(:configured?).and_return(true)
        allow(GeminiConfig).to receive(:generate_content).and_raise(StandardError.new("API error"))
      end

      it "marks video as failed with error message" do
        expect { described_class.analyze_video(video) }.to raise_error(StandardError)

        expect(video.reload.analysis_status).to eq("failed")
        expect(video.analysis_error).to eq("API error")
      end
    end
  end

  describe ".analyze_pending_videos" do
    let!(:pending_videos) { create_list(:youtube_video, 3, youtube_channel: channel) }
    let!(:completed_video) { create(:youtube_video, :completed, youtube_channel: channel) }

    before do
      allow(GeminiConfig).to receive(:configured?).and_return(true)
      allow(GeminiConfig).to receive(:generate_content).and_return({
        category: "strength",
        difficulty_level: "intermediate",
        language: "ko",
        knowledge_chunks: []
      }.to_json)
    end

    it "only analyzes pending videos" do
      results = described_class.analyze_pending_videos(limit: 10)

      expect(results.count).to eq(3)
      expect(results.all? { |r| r[:success] }).to be true
    end

    it "respects limit parameter" do
      results = described_class.analyze_pending_videos(limit: 2)

      expect(results.count).to eq(2)
    end

    it "filters by channel when provided" do
      other_channel = create(:youtube_channel)
      create(:youtube_video, youtube_channel: other_channel)

      results = described_class.analyze_pending_videos(channel: channel)

      expect(results.count).to eq(3) # Only videos from our channel
    end
  end
end
