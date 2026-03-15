# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExerciseVideoClipService do
  let(:channel) { create(:youtube_channel) }
  let(:video) { create(:youtube_video, youtube_channel: channel) }

  let!(:bench_technique) do
    create(:exercise_video_clip, :technique,
      youtube_video: video,
      exercise_name: "bench_press",
      source_language: "ko",
      summary: "어깨 견갑골을 모아 수행하세요.",
      timestamp_start: 10.0,
      timestamp_end: 40.0)
  end

  let!(:bench_form) do
    create(:exercise_video_clip, :form_check,
      youtube_video: video,
      exercise_name: "bench_press",
      source_language: "ko",
      summary: "팔꿈치 각도 45도를 유지합니다.",
      timestamp_start: 60.0,
      timestamp_end: 90.0)
  end

  let!(:bench_en) do
    create(:exercise_video_clip, :technique,
      youtube_video: video,
      exercise_name: "bench_press",
      source_language: "en",
      summary: "Keep shoulder blades retracted.",
      timestamp_start: 5.0,
      timestamp_end: 30.0)
  end

  let!(:squat_clip) do
    create(:exercise_video_clip, :technique,
      youtube_video: video,
      exercise_name: "squat",
      source_language: "ko",
      summary: "무릎이 발끝을 넘지 않게 하세요.",
      timestamp_start: 15.0,
      timestamp_end: 45.0)
  end

  describe ".clips_for_exercise" do
    context "with matching locale" do
      it "returns clips for the exercise in the given locale" do
        result = described_class.clips_for_exercise("bench_press", locale: "ko")
        expect(result).to include(bench_technique, bench_form)
        expect(result).not_to include(bench_en)
      end

      it "respects the limit parameter" do
        result = described_class.clips_for_exercise("bench_press", locale: "ko", limit: 1)
        expect(result.size).to eq(1)
      end

      it "orders by clip_type then timestamp_start" do
        result = described_class.clips_for_exercise("bench_press", locale: "ko")
        types = result.map(&:clip_type)
        expect(types).to eq(types.sort)
      end
    end

    context "when no clips match the locale" do
      it "falls back to all locale clips for the exercise" do
        result = described_class.clips_for_exercise("bench_press", locale: "ja")
        expect(result).to include(bench_technique, bench_form, bench_en)
      end
    end

    context "with normalized name" do
      it "normalizes spaces to underscores" do
        result = described_class.clips_for_exercise("bench press", locale: "ko")
        expect(result).to include(bench_technique, bench_form)
      end

      it "normalizes uppercase to lowercase" do
        result = described_class.clips_for_exercise("BENCH_PRESS", locale: "ko")
        expect(result).to include(bench_technique, bench_form)
      end
    end
  end

  describe ".batch_clips" do
    it "returns a hash keyed by exercise_name" do
      result = described_class.batch_clips(%w[bench_press squat], locale: "ko")
      expect(result.keys).to include("bench_press", "squat")
    end

    it "filters by locale" do
      result = described_class.batch_clips(%w[bench_press], locale: "ko")
      clips = result["bench_press"] || []
      expect(clips).not_to include(bench_en)
    end
  end

  describe ".format_clip_reference" do
    it "returns a hash with all required keys" do
      ref = described_class.format_clip_reference(bench_technique)
      expect(ref).to include(
        :title, :url, :video_id, :channel, :clip_type, :timestamp_start, :timestamp_end, :summary
      )
    end

    it "builds the youtube URL with timestamp" do
      ref = described_class.format_clip_reference(bench_technique)
      expect(ref[:url]).to include("youtube.com/watch")
      expect(ref[:url]).to include("&t=10")
    end

    it "includes clip_type" do
      ref = described_class.format_clip_reference(bench_technique)
      expect(ref[:clip_type]).to eq("technique")
    end
  end
end
