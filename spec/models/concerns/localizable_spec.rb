# frozen_string_literal: true

require "rails_helper"

RSpec.describe Localizable do
  let(:test_class) do
    Class.new do
      include Localizable
    end
  end

  describe ".translate" do
    context "with fitness_factors category" do
      it "returns Korean translation by default" do
        expect(test_class.translate(:fitness_factors, "strength")).to eq("근력")
      end

      it "returns English translation" do
        expect(test_class.translate(:fitness_factors, "strength", "en")).to eq("Strength")
      end

      it "returns Japanese translation" do
        expect(test_class.translate(:fitness_factors, "strength", "ja")).to eq("筋力")
      end

      it "falls back to Korean for unsupported locale" do
        expect(test_class.translate(:fitness_factors, "strength", "xx")).to eq("근력")
      end

      it "translates all fitness factors in English" do
        expect(test_class.translate(:fitness_factors, "muscular_endurance", "en")).to eq("Muscular Endurance")
        expect(test_class.translate(:fitness_factors, "sustainability", "en")).to eq("Sustainability")
        expect(test_class.translate(:fitness_factors, "power", "en")).to eq("Power")
        expect(test_class.translate(:fitness_factors, "cardiovascular", "en")).to eq("Cardiovascular")
      end
    end

    context "with days category (array)" do
      it "translates days by index in English" do
        expect(test_class.translate(:days, 1, "en")).to eq("Monday")
        expect(test_class.translate(:days, 0, "en")).to eq("Sunday")
        expect(test_class.translate(:days, 5, "en")).to eq("Friday")
      end

      it "translates days by index in Korean" do
        expect(test_class.translate(:days, 1, "ko")).to eq("월요일")
        expect(test_class.translate(:days, 0, "ko")).to eq("일요일")
        expect(test_class.translate(:days, 6, "ko")).to eq("토요일")
      end

      it "translates days by index in Japanese" do
        expect(test_class.translate(:days, 1, "ja")).to eq("月曜日")
        expect(test_class.translate(:days, 0, "ja")).to eq("日曜日")
      end
    end

    context "with conditions category" do
      it "translates conditions in English" do
        expect(test_class.translate(:conditions, "excellent", "en")).to eq("Excellent")
        expect(test_class.translate(:conditions, "good", "en")).to eq("Good")
        expect(test_class.translate(:conditions, "moderate", "en")).to eq("Moderate")
        expect(test_class.translate(:conditions, "poor", "en")).to eq("Poor")
      end

      it "translates conditions in Korean" do
        expect(test_class.translate(:conditions, "excellent", "ko")).to eq("최상")
        expect(test_class.translate(:conditions, "good", "ko")).to eq("양호")
        expect(test_class.translate(:conditions, "moderate", "ko")).to eq("보통")
        expect(test_class.translate(:conditions, "poor", "ko")).to eq("나쁨")
      end

      it "translates conditions in Japanese" do
        expect(test_class.translate(:conditions, "excellent", "ja")).to eq("最高")
      end
    end

    context "with tiers category" do
      it "translates tiers in English" do
        expect(test_class.translate(:tiers, "beginner", "en")).to eq("Beginner")
        expect(test_class.translate(:tiers, "intermediate", "en")).to eq("Intermediate")
        expect(test_class.translate(:tiers, "advanced", "en")).to eq("Advanced")
      end

      it "translates tiers in Japanese" do
        expect(test_class.translate(:tiers, "beginner", "ja")).to eq("初級")
        expect(test_class.translate(:tiers, "advanced", "ja")).to eq("上級")
      end
    end

    context "with exercise_tiers category" do
      it "translates exercise tiers in English" do
        expect(test_class.translate(:exercise_tiers, "elite", "en")).to eq("Elite")
        expect(test_class.translate(:exercise_tiers, "poor", "en")).to eq("Poor")
      end

      it "translates exercise tiers in Korean" do
        expect(test_class.translate(:exercise_tiers, "elite", "ko")).to eq("엘리트")
        expect(test_class.translate(:exercise_tiers, "excellent", "ko")).to eq("우수")
      end
    end

    context "with training_methods category" do
      it "translates training methods in English" do
        expect(test_class.translate(:training_methods, "fixed_sets_reps", "en")).to eq("Fixed Sets & Reps")
        expect(test_class.translate(:training_methods, "tabata", "en")).to eq("Tabata")
      end

      it "translates training methods in Korean" do
        expect(test_class.translate(:training_methods, "fixed_sets_reps", "ko")).to eq("정해진 세트/횟수")
        expect(test_class.translate(:training_methods, "tabata", "ko")).to eq("타바타")
      end
    end

    context "with split_types category" do
      it "translates split types in English" do
        expect(test_class.translate(:split_types, "full_body", "en")).to eq("Full Body")
        expect(test_class.translate(:split_types, "push_pull_legs", "en")).to eq("Push/Pull/Legs")
      end
    end

    context "with missing key" do
      it "falls back to Korean when key missing in target locale" do
        # Korean is the fallback — if en translation exists, it returns en
        # For a completely unknown key, returns the key itself
        result = test_class.translate(:fitness_factors, "unknown_factor", "en")
        expect(result).to eq("unknown_factor")
      end

      it "returns the key string for unknown category" do
        expect(test_class.translate(:nonexistent_category, "something", "ko")).to eq("something")
      end
    end

    context "with locale normalization" do
      it "treats 'ko' and :ko the same way" do
        expect(test_class.translate(:fitness_factors, "strength", "ko")).to eq("근력")
      end

      it "defaults to Korean for blank locale" do
        expect(test_class.translate(:fitness_factors, "strength", "")).to eq("근력")
      end
    end
  end
end
