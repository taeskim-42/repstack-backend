# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagSearchService do
  let!(:bench_technique) do
    create(:fitness_knowledge_chunk,
      :exercise_technique,
      exercise_name: "bench_press",
      muscle_group: "chest",
      content: "벤치프레스는 가슴 운동의 핵심입니다.")
  end

  let!(:squat_form) do
    create(:fitness_knowledge_chunk,
      :form_check,
      exercise_name: "squat",
      muscle_group: "legs",
      content: "스쿼트 시 무릎 방향에 주의하세요.")
  end

  let!(:nutrition_chunk) do
    create(:fitness_knowledge_chunk,
      :nutrition_recovery,
      content: "운동 후 단백질 섭취가 중요합니다.")
  end

  describe ".search" do
    it "returns empty array for blank query" do
      expect(described_class.search("")).to eq([])
      expect(described_class.search(nil)).to eq([])
    end

    context "with keyword search" do
      before do
        allow(EmbeddingService).to receive(:pgvector_available?).and_return(false)
      end

      it "finds matching chunks by keyword" do
        results = described_class.search("벤치프레스")

        expect(results.map { |r| r[:id] }).to include(bench_technique.id)
      end

      it "filters by knowledge type" do
        results = described_class.search("운동", knowledge_types: ["form_check"])

        expect(results.map { |r| r[:type] }).to all(eq("form_check"))
      end
    end
  end

  describe ".search_for_exercise" do
    it "finds chunks for specific exercise" do
      results = described_class.search_for_exercise("bench")

      expect(results.length).to be >= 1
      expect(results.first[:exercise_name]).to eq("bench_press")
    end

    it "filters by knowledge type" do
      results = described_class.search_for_exercise("squat", knowledge_types: ["form_check"])

      expect(results.first[:type]).to eq("form_check")
    end
  end

  describe ".search_for_muscle_group" do
    it "finds chunks for specific muscle group" do
      results = described_class.search_for_muscle_group("chest")

      expect(results.length).to be >= 1
      expect(results.first[:muscle_group]).to eq("chest")
    end
  end

  describe ".contextual_search" do
    it "combines exercise and muscle group searches" do
      results = described_class.contextual_search(
        exercises: ["bench"],
        muscle_groups: ["legs"],
        limit: 10
      )

      ids = results.map { |r| r[:id] }
      # Should find bench (matches exercise) and squat (matches muscle group legs)
      expect(ids).to include(bench_technique.id)
    end

    it "includes nutrition for weight loss goal" do
      results = described_class.contextual_search(
        goals: ["weight_loss"],
        limit: 10
      )

      types = results.map { |r| r[:type] }
      expect(types).to include("nutrition_recovery")
    end

    it "filters by difficulty level" do
      intermediate = create(:fitness_knowledge_chunk, difficulty_level: "intermediate", exercise_name: "lat_pulldown")
      advanced = create(:fitness_knowledge_chunk, difficulty_level: "advanced", exercise_name: "muscle_up")

      results = described_class.contextual_search(
        exercises: ["lat_pulldown", "muscle_up"],
        difficulty_level: "intermediate",
        limit: 20
      )

      difficulty_levels = results.map { |r| r[:difficulty_level] }.compact
      expect(difficulty_levels).not_to include("advanced")
    end
  end

  describe ".build_context_prompt" do
    it "returns empty string for empty chunks" do
      expect(described_class.build_context_prompt([])).to eq("")
    end

    it "builds formatted prompt from chunks" do
      chunks = [
        {
          type: "exercise_technique",
          summary: "벤치프레스 자세",
          content: "가슴을 활짝 펴고 수행하세요.",
          exercise_name: "bench_press",
          muscle_group: "chest"
        }
      ]

      prompt = described_class.build_context_prompt(chunks)

      expect(prompt).to include("참고 지식")
      expect(prompt).to include("벤치프레스 자세")
      expect(prompt).to include("가슴을 활짝 펴고")
    end
  end

  describe ".trending_knowledge" do
    it "returns knowledge from popular videos" do
      popular_video = create(:youtube_video, :completed, view_count: 50_000)
      create(:fitness_knowledge_chunk, youtube_video: popular_video)

      results = described_class.trending_knowledge(limit: 5)

      expect(results.length).to be >= 1
    end
  end
end
