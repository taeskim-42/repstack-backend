# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExerciseVideoClipService do
  let(:channel) { create(:youtube_channel) }
  let(:video1) { create(:youtube_video, youtube_channel: channel) }
  let(:video2) { create(:youtube_video, youtube_channel: channel) }
  let(:video3) { create(:youtube_video, youtube_channel: channel) }

  describe ".clips_for_exercise" do
    before do
      create(:exercise_video_clip, :technique, youtube_video: video1, exercise_name: "squat", source_language: "ko")
      create(:exercise_video_clip, :form_check, youtube_video: video1, exercise_name: "squat", source_language: "ko")
      create(:exercise_video_clip, :technique, youtube_video: video2, exercise_name: "deadlift", source_language: "ko")
    end

    it "returns clips for the given exercise" do
      results = described_class.clips_for_exercise("squat")
      expect(results.length).to eq(2)
      expect(results.map(&:exercise_name).uniq).to eq(["squat"])
    end

    it "respects the limit" do
      results = described_class.clips_for_exercise("squat", limit: 1)
      expect(results.length).to eq(1)
    end

    it "falls back to all languages when locale has no results" do
      create(:exercise_video_clip, :technique, youtube_video: video3, exercise_name: "pullup", source_language: "en")
      results = described_class.clips_for_exercise("pullup", locale: "ko")
      expect(results.length).to eq(1)
    end

    it "returns empty for unknown exercise" do
      expect(described_class.clips_for_exercise("unknown_exercise")).to be_empty
    end
  end

  describe ".diverse_clips_for_exercise" do
    before do
      create(:exercise_video_clip, :technique,       youtube_video: video1, exercise_name: "bench_press", source_language: "ko")
      create(:exercise_video_clip, :form_check,      youtube_video: video2, exercise_name: "bench_press", source_language: "ko")
      create(:exercise_video_clip, :pro_tip,         youtube_video: video3, exercise_name: "bench_press", source_language: "ko")
    end

    it "returns up to limit clips" do
      results = described_class.diverse_clips_for_exercise("bench_press", limit: 3)
      expect(results.length).to eq(3)
    end

    it "selects one clip per type in priority order" do
      results = described_class.diverse_clips_for_exercise("bench_press", limit: 3)
      types = results.map(&:clip_type)
      expect(types).to include("technique", "form_check", "pro_tip")
    end

    it "returns empty array for unknown exercise" do
      results = described_class.diverse_clips_for_exercise("unknown_xyz")
      expect(results).to eq([])
    end

    it "falls back to all languages when locale scope is empty" do
      create(:exercise_video_clip, :technique, youtube_video: video1, exercise_name: "lunge", source_language: "en")
      results = described_class.diverse_clips_for_exercise("lunge", locale: "ko", limit: 1)
      expect(results.length).to eq(1)
    end

    it "avoids duplicate youtube_video_ids across selected clips" do
      # All clips on the same video — only one should be selected per iteration
      video_single = create(:youtube_video, youtube_channel: channel)
      create(:exercise_video_clip, :technique,  youtube_video: video_single, exercise_name: "plank", source_language: "ko")
      create(:exercise_video_clip, :form_check, youtube_video: video_single, exercise_name: "plank", source_language: "ko")

      results = described_class.diverse_clips_for_exercise("plank", limit: 3)
      video_ids = results.map(&:youtube_video_id)
      expect(video_ids.uniq.length).to eq(video_ids.length)
    end

    it "respects the limit when fewer clip types exist than limit" do
      results = described_class.diverse_clips_for_exercise("bench_press", limit: 2)
      expect(results.length).to eq(2)
    end

    it "normalizes exercise name (spaces to underscores)" do
      results = described_class.diverse_clips_for_exercise("bench press", limit: 3)
      expect(results.length).to eq(3)
    end
  end

  describe ".format_clip_reference" do
    let(:clip) do
      create(:exercise_video_clip, :technique,
        youtube_video: video1,
        exercise_name: "squat",
        title: "Squat Technique Guide",
        summary: "Keep your back straight",
        timestamp_start: 30.5,
        timestamp_end: 120.0,
        source_language: "ko")
    end

    it "returns a hash with all required fields" do
      result = described_class.format_clip_reference(clip)

      expect(result[:title]).to eq("Squat Technique Guide")
      expect(result[:url]).to include(video1.video_id)
      expect(result[:video_id]).to eq(video1.video_id)
      expect(result[:clip_type]).to eq("technique")
      expect(result[:timestamp_start]).to eq(30.5)
      expect(result[:timestamp_end]).to eq(120.0)
      expect(result[:summary]).to eq("Keep your back straight")
    end

    it "includes timestamp in the URL" do
      result = described_class.format_clip_reference(clip)
      expect(result[:url]).to include("&t=30")
    end
  end

  describe ".batch_clips" do
    before do
      create(:exercise_video_clip, :technique, youtube_video: video1, exercise_name: "squat",      source_language: "ko")
      create(:exercise_video_clip, :form_check, youtube_video: video2, exercise_name: "deadlift",  source_language: "ko")
    end

    it "groups clips by exercise name" do
      result = described_class.batch_clips(["squat", "deadlift"])
      expect(result.keys).to match_array(["squat", "deadlift"])
    end

    it "returns empty hash when no matches" do
      result = described_class.batch_clips(["unknown"])
      expect(result).to eq({})
    end
  end
end
