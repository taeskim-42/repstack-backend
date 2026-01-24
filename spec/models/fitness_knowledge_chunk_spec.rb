# frozen_string_literal: true

require "rails_helper"

RSpec.describe FitnessKnowledgeChunk, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:youtube_video) }
  end

  describe "validations" do
    subject { build(:fitness_knowledge_chunk) }

    it { is_expected.to validate_presence_of(:knowledge_type) }
    it { is_expected.to validate_inclusion_of(:knowledge_type).in_array(FitnessKnowledgeChunk::KNOWLEDGE_TYPES) }
    it { is_expected.to validate_presence_of(:content) }
  end

  describe "scopes" do
    let!(:technique) { create(:fitness_knowledge_chunk, :exercise_technique) }
    let!(:routine) { create(:fitness_knowledge_chunk, :routine_design) }
    let!(:nutrition) { create(:fitness_knowledge_chunk, :nutrition_recovery) }
    let!(:form) { create(:fitness_knowledge_chunk, :form_check) }

    describe ".exercise_techniques" do
      it "returns exercise technique chunks" do
        expect(described_class.exercise_techniques).to contain_exactly(technique)
      end
    end

    describe ".routine_designs" do
      it "returns routine design chunks" do
        expect(described_class.routine_designs).to contain_exactly(routine)
      end
    end

    describe ".nutrition_recovery" do
      it "returns nutrition/recovery chunks" do
        expect(described_class.nutrition_recovery).to contain_exactly(nutrition)
      end
    end

    describe ".form_checks" do
      it "returns form check chunks" do
        expect(described_class.form_checks).to contain_exactly(form)
      end
    end

    describe ".for_exercise" do
      let!(:bench_chunk) { create(:fitness_knowledge_chunk, exercise_name: "bench_press") }
      let!(:squat_chunk) { create(:fitness_knowledge_chunk, exercise_name: "squat") }

      it "returns chunks for the specified exercise" do
        expect(described_class.for_exercise("bench")).to include(bench_chunk)
        expect(described_class.for_exercise("bench")).not_to include(squat_chunk)
      end
    end

    describe ".for_muscle_group" do
      let!(:chest_chunk) { create(:fitness_knowledge_chunk, muscle_group: "chest") }
      let!(:legs_chunk) { create(:fitness_knowledge_chunk, muscle_group: "legs") }

      it "returns chunks for the specified muscle group" do
        expect(described_class.for_muscle_group("chest")).to include(chest_chunk)
        expect(described_class.for_muscle_group("chest")).not_to include(legs_chunk)
      end
    end
  end

  describe ".keyword_search" do
    let!(:bench_chunk) { create(:fitness_knowledge_chunk, content: "벤치프레스 자세 가이드", summary: "벤치프레스") }
    let!(:squat_chunk) { create(:fitness_knowledge_chunk, content: "스쿼트 운동법", summary: "스쿼트") }

    it "searches content by keyword" do
      results = described_class.keyword_search("벤치")
      expect(results).to include(bench_chunk)
      expect(results).not_to include(squat_chunk)
    end
  end

  describe ".relevant_for_context" do
    let!(:bench_chest) { create(:fitness_knowledge_chunk, exercise_name: "bench_press", muscle_group: "chest") }
    let!(:squat_legs) { create(:fitness_knowledge_chunk, exercise_name: "squat", muscle_group: "legs") }
    let!(:deadlift_back) { create(:fitness_knowledge_chunk, :for_deadlift) }

    it "filters by exercise names" do
      results = described_class.relevant_for_context(exercise_names: ["bench"])
      expect(results).to include(bench_chest)
      expect(results).not_to include(squat_legs)
    end

    it "filters by muscle groups" do
      results = described_class.relevant_for_context(muscle_groups: ["chest"])
      expect(results).to include(bench_chest)
      expect(results).not_to include(squat_legs)
    end

    it "filters by knowledge types" do
      routine = create(:fitness_knowledge_chunk, :routine_design)
      results = described_class.relevant_for_context(knowledge_types: ["routine_design"])
      expect(results).to include(routine)
      expect(results).not_to include(bench_chest)
    end
  end

  describe "#video_timestamp_url" do
    let(:video) { create(:youtube_video, video_id: "abc123") }
    let(:chunk) { create(:fitness_knowledge_chunk, youtube_video: video, timestamp_start: 120) }

    it "returns URL with timestamp" do
      expect(chunk.video_timestamp_url).to eq("https://www.youtube.com/watch?v=abc123&t=120")
    end

    context "without timestamp" do
      let(:chunk) { create(:fitness_knowledge_chunk, youtube_video: video, timestamp_start: nil) }

      it "returns URL without timestamp" do
        expect(chunk.video_timestamp_url).to eq("https://www.youtube.com/watch?v=abc123")
      end
    end
  end

  describe "#source_reference" do
    let(:channel) { create(:youtube_channel, name: "Test Channel") }
    let(:video) { create(:youtube_video, youtube_channel: channel, title: "Test Video", video_id: "xyz789") }
    let(:chunk) { create(:fitness_knowledge_chunk, youtube_video: video, timestamp_start: 60) }

    it "returns source reference hash" do
      ref = chunk.source_reference

      expect(ref[:video_title]).to eq("Test Video")
      expect(ref[:video_url]).to include("xyz789")
      expect(ref[:channel_name]).to eq("Test Channel")
      expect(ref[:timestamp]).to eq(60)
    end
  end
end
