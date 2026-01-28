# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeKnowledgeExtractionService do
  let(:channel) { create(:youtube_channel) }
  let(:video) { create(:youtube_video, youtube_channel: channel, transcript: sample_transcript) }
  let(:sample_transcript) do
    "[00:00] 안녕하세요 오늘은 벤치프레스에 대해 알아보겠습니다 [00:10] 벤치프레스는 가슴 운동의 기본입니다"
  end

  describe ".configured?" do
    it "returns true when Anthropic API is configured" do
      allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(true)
      expect(described_class.configured?).to be true
    end

    it "returns false when Anthropic API is not configured" do
      allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(false)
      expect(described_class.configured?).to be false
    end
  end

  describe ".analyze_video" do
    context "when Claude is not configured" do
      before do
        allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(false)
      end

      it "raises an error" do
        expect { described_class.analyze_video(video) }.to raise_error("Claude API not configured")
      end
    end

    context "when video has no transcript" do
      let(:video) { create(:youtube_video, youtube_channel: channel, transcript: nil) }

      it "returns error without calling API" do
        result = described_class.analyze_video(video)
        expect(result[:error]).to eq("No transcript available")
      end
    end

    context "when Claude is configured" do
      let(:claude_response) do
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
              difficulty_level: "intermediate",
              timestamp_start: 0,
              timestamp_end: 10
            },
            {
              type: "form_check",
              content: "견갑골을 모아 안정적인 자세를 만드세요. 어깨가 앞으로 나오면 부상 위험이 있습니다.",
              summary: "견갑골 위치",
              exercise_name: "bench_press",
              muscle_group: "chest",
              timestamp_start: 10,
              timestamp_end: 20
            }
          ]
        }
      end

      before do
        allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(true)
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: true,
          content: claude_response.to_json
        })
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

      it "extracts timestamps from chunks" do
        described_class.analyze_video(video)

        chunk = video.fitness_knowledge_chunks.first
        expect(chunk.timestamp_start).to be_present
        expect(chunk.timestamp_end).to be_present
      end
    end

    context "when video is already analyzed" do
      let(:video) { create(:youtube_video, :completed, youtube_channel: channel, transcript: sample_transcript) }

      it "returns error without calling API" do
        expect(AiTrainer::LlmGateway).not_to receive(:chat)
        result = described_class.analyze_video(video)
        expect(result[:error]).to eq("Already analyzed")
      end
    end

    context "when analysis fails" do
      before do
        allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(true)
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: "API error"
        })
      end

      it "marks video as failed with error message" do
        expect { described_class.analyze_video(video) }.to raise_error(/LLM API error/)

        expect(video.reload.analysis_status).to eq("failed")
        expect(video.analysis_error).to include("API error")
      end
    end
  end

  describe ".analyze_pending_videos" do
    let!(:pending_video_with_transcript) do
      create(:youtube_video, youtube_channel: channel, transcript: sample_transcript)
    end
    let!(:pending_video_without_transcript) do
      create(:youtube_video, youtube_channel: channel, transcript: nil)
    end
    let!(:completed_video) do
      create(:youtube_video, :completed, youtube_channel: channel, transcript: sample_transcript)
    end

    before do
      allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(true)
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: true,
        content: {
          category: "strength",
          difficulty_level: "intermediate",
          language: "ko",
          knowledge_chunks: []
        }.to_json
      })
    end

    it "only analyzes pending videos with transcripts" do
      results = described_class.analyze_pending_videos(limit: 10)

      # Only the pending video with transcript should be analyzed
      expect(results.count).to eq(1)
      expect(results.first[:success]).to be true
    end

    it "respects limit parameter" do
      create(:youtube_video, youtube_channel: channel, transcript: sample_transcript)

      results = described_class.analyze_pending_videos(limit: 1)

      expect(results.count).to eq(1)
    end
  end

  describe ".analyze_transcript" do
    let(:transcript) { "[00:00] 테스트 자막입니다" }

    before do
      allow(AiTrainer::LlmGateway).to receive(:configured?).with(task: :knowledge_extraction).and_return(true)
    end

    it "calls LlmGateway with correct task" do
      expect(AiTrainer::LlmGateway).to receive(:chat).with(
        hash_including(task: :knowledge_extraction)
      ).and_return({ success: true, content: { knowledge_chunks: [] }.to_json })

      described_class.analyze_transcript(transcript)
    end

    it "parses JSON response correctly" do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: true,
        content: { category: "strength", knowledge_chunks: [] }.to_json
      })

      result = described_class.analyze_transcript(transcript)

      expect(result[:category]).to eq("strength")
    end
  end
end
