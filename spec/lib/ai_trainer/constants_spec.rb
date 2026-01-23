# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::Constants do
  describe '.fitness_factor_for_day' do
    it 'returns strength for Monday' do
      expect(described_class.fitness_factor_for_day(1)).to eq(:strength)
    end

    it 'returns muscular_endurance for Tuesday' do
      expect(described_class.fitness_factor_for_day(2)).to eq(:muscular_endurance)
    end

    it 'returns sustainability for Wednesday' do
      expect(described_class.fitness_factor_for_day(3)).to eq(:sustainability)
    end

    it 'returns strength for Thursday' do
      expect(described_class.fitness_factor_for_day(4)).to eq(:strength)
    end

    it 'returns cardiovascular for Friday' do
      expect(described_class.fitness_factor_for_day(5)).to eq(:cardiovascular)
    end

    it 'returns nil for invalid day' do
      expect(described_class.fitness_factor_for_day(6)).to be_nil
    end
  end

  describe '.level_info' do
    it 'returns level data for valid level' do
      info = described_class.level_info(3)
      expect(info[:tier]).to eq('intermediate')
      expect(info[:weight_multiplier]).to eq(0.7)
    end

    it 'returns nil for invalid level' do
      expect(described_class.level_info(99)).to be_nil
    end
  end

  describe '.tier_for_level' do
    it 'returns beginner for levels 1-2' do
      expect(described_class.tier_for_level(1)).to eq('beginner')
      expect(described_class.tier_for_level(2)).to eq('beginner')
    end

    it 'returns intermediate for levels 3-5' do
      expect(described_class.tier_for_level(3)).to eq('intermediate')
      expect(described_class.tier_for_level(4)).to eq('intermediate')
      expect(described_class.tier_for_level(5)).to eq('intermediate')
    end

    it 'returns advanced for levels 6-8' do
      expect(described_class.tier_for_level(6)).to eq('advanced')
      expect(described_class.tier_for_level(7)).to eq('advanced')
      expect(described_class.tier_for_level(8)).to eq('advanced')
    end

    it 'returns nil for invalid level' do
      expect(described_class.tier_for_level(99)).to be_nil
    end
  end

  describe '.weight_multiplier_for_level' do
    it 'returns correct multiplier for each level' do
      expect(described_class.weight_multiplier_for_level(1)).to eq(0.5)
      expect(described_class.weight_multiplier_for_level(4)).to eq(0.8)
      expect(described_class.weight_multiplier_for_level(8)).to eq(1.2)
    end

    it 'returns 1.0 for invalid level' do
      expect(described_class.weight_multiplier_for_level(99)).to eq(1.0)
    end
  end

  describe '.exercises_for_muscle' do
    it 'returns chest exercises' do
      exercises = described_class.exercises_for_muscle(:chest)
      expect(exercises).to be_an(Array)
      expect(exercises.first[:name]).to eq('푸시업')
    end

    it 'returns back exercises' do
      exercises = described_class.exercises_for_muscle(:back)
      expect(exercises).to be_an(Array)
      expect(exercises.first[:name]).to eq('턱걸이')
    end

    it 'returns legs exercises' do
      exercises = described_class.exercises_for_muscle(:legs)
      expect(exercises).to be_an(Array)
    end

    it 'returns empty array for invalid muscle group' do
      expect(described_class.exercises_for_muscle(:invalid)).to eq([])
    end

    it 'handles string input' do
      exercises = described_class.exercises_for_muscle('chest')
      expect(exercises).to be_an(Array)
    end
  end

  describe '.calculate_condition_score' do
    it 'calculates score with default values' do
      score = described_class.calculate_condition_score({})
      expect(score).to eq(3.0) # All defaults to 3
    end

    it 'calculates higher score for good condition' do
      inputs = { sleep: 5, fatigue: 1, stress: 1, soreness: 1, motivation: 5 }
      score = described_class.calculate_condition_score(inputs)
      expect(score).to eq(5.0)
    end

    it 'calculates lower score for poor condition' do
      inputs = { sleep: 1, fatigue: 5, stress: 5, soreness: 5, motivation: 1 }
      score = described_class.calculate_condition_score(inputs)
      expect(score).to eq(1.0)
    end

    it 'inverts negative factors (fatigue, stress, soreness)' do
      # Higher fatigue should lower score
      low_fatigue = described_class.calculate_condition_score({ fatigue: 1 })
      high_fatigue = described_class.calculate_condition_score({ fatigue: 5 })
      expect(low_fatigue).to be > high_fatigue
    end

    it 'handles partial inputs' do
      score = described_class.calculate_condition_score({ sleep: 5, motivation: 5 })
      expect(score).to be > 3.0
    end
  end

  describe '.adjustment_for_condition_score' do
    it 'returns excellent for score >= 4.0' do
      adjustment = described_class.adjustment_for_condition_score(4.5)
      expect(adjustment[:korean]).to eq('최상')
      expect(adjustment[:volume_modifier]).to eq(1.1)
    end

    it 'returns good for score 3.0-3.9' do
      adjustment = described_class.adjustment_for_condition_score(3.5)
      expect(adjustment[:korean]).to eq('양호')
      expect(adjustment[:volume_modifier]).to eq(1.0)
    end

    it 'returns moderate for score 2.0-2.9' do
      adjustment = described_class.adjustment_for_condition_score(2.5)
      expect(adjustment[:korean]).to eq('보통')
      expect(adjustment[:volume_modifier]).to eq(0.85)
    end

    it 'returns poor for score < 2.0' do
      adjustment = described_class.adjustment_for_condition_score(1.5)
      expect(adjustment[:korean]).to eq('나쁨')
      expect(adjustment[:volume_modifier]).to eq(0.7)
    end

    it 'returns good as default for edge cases' do
      adjustment = described_class.adjustment_for_condition_score(0)
      expect(adjustment[:korean]).to eq('양호')
    end
  end

  describe '.calculate_target_weight' do
    it 'calculates bench press weight' do
      weight = described_class.calculate_target_weight(
        exercise_type: :bench,
        height: 175,
        level: 3
      )
      # (175 - 100) * 0.7 = 52.5
      expect(weight).to eq(52.5)
    end

    it 'calculates squat weight' do
      weight = described_class.calculate_target_weight(
        exercise_type: :squat,
        height: 175,
        level: 3
      )
      # (175 - 100 + 20) * 0.7 = 66.5
      expect(weight).to eq(66.5)
    end

    it 'calculates deadlift weight' do
      weight = described_class.calculate_target_weight(
        exercise_type: :deadlift,
        height: 175,
        level: 3
      )
      # (175 - 100 + 40) * 0.7 = 80.5
      expect(weight).to eq(80.5)
    end

    it 'returns nil for unknown exercise type' do
      weight = described_class.calculate_target_weight(
        exercise_type: :unknown,
        height: 175,
        level: 3
      )
      expect(weight).to be_nil
    end

    it 'handles string exercise type' do
      weight = described_class.calculate_target_weight(
        exercise_type: 'bench',
        height: 175,
        level: 3
      )
      expect(weight).to eq(52.5)
    end
  end

  describe '.training_method_for_factor' do
    it 'returns fixed_sets_reps for strength' do
      method = described_class.training_method_for_factor(:strength)
      expect(method).to eq(:fixed_sets_reps)
    end

    it 'returns total_reps_fill for muscular_endurance' do
      method = described_class.training_method_for_factor(:muscular_endurance)
      expect(method).to eq(:total_reps_fill)
    end

    it 'returns max_sets_at_fixed_reps for sustainability' do
      method = described_class.training_method_for_factor(:sustainability)
      expect(method).to eq(:max_sets_at_fixed_reps)
    end

    it 'returns tabata for cardiovascular' do
      method = described_class.training_method_for_factor(:cardiovascular)
      expect(method).to eq(:tabata)
    end

    it 'returns explosive for power' do
      method = described_class.training_method_for_factor(:power)
      expect(method).to eq(:explosive)
    end

    it 'handles string input' do
      method = described_class.training_method_for_factor('strength')
      expect(method).to eq(:fixed_sets_reps)
    end

    it 'returns nil for unknown factor' do
      method = described_class.training_method_for_factor(:unknown)
      expect(method).to be_nil
    end
  end

  describe 'CONSTANTS' do
    describe 'FITNESS_FACTORS' do
      it 'has all required factors' do
        expect(described_class::FITNESS_FACTORS.keys).to include(
          :strength, :muscular_endurance, :sustainability, :power, :cardiovascular
        )
      end

      it 'each factor has required fields' do
        described_class::FITNESS_FACTORS.each do |_key, factor|
          expect(factor).to have_key(:id)
          expect(factor).to have_key(:korean)
          expect(factor).to have_key(:training_method)
        end
      end
    end

    describe 'LEVELS' do
      it 'has 8 levels' do
        expect(described_class::LEVELS.keys).to eq([ 1, 2, 3, 4, 5, 6, 7, 8 ])
      end

      it 'each level has required fields' do
        described_class::LEVELS.each do |_level, info|
          expect(info).to have_key(:tier)
          expect(info).to have_key(:weight_multiplier)
        end
      end
    end

    describe 'EXERCISES' do
      it 'has all muscle groups' do
        expect(described_class::EXERCISES.keys).to include(
          :chest, :back, :legs, :shoulders, :arms, :core, :cardio
        )
      end

      it 'each muscle group has exercises' do
        described_class::EXERCISES.each do |_group, data|
          expect(data[:exercises]).to be_an(Array)
          expect(data[:exercises]).not_to be_empty
        end
      end
    end

    describe 'CONDITION_INPUTS' do
      it 'has all condition inputs' do
        expect(described_class::CONDITION_INPUTS.keys).to include(
          :sleep, :fatigue, :stress, :soreness, :motivation
        )
      end

      it 'weights sum to 1.0' do
        total_weight = described_class::CONDITION_INPUTS.values.sum { |v| v[:weight] }
        expect(total_weight).to eq(1.0)
      end
    end

    describe 'LEVEL_TEST_CRITERIA' do
      it 'has criteria for all 8 levels' do
        expect(described_class::LEVEL_TEST_CRITERIA.keys).to eq([ 1, 2, 3, 4, 5, 6, 7, 8 ])
      end

      it 'each criteria has lift ratios' do
        described_class::LEVEL_TEST_CRITERIA.each do |_level, criteria|
          expect(criteria).to have_key(:bench_ratio)
          expect(criteria).to have_key(:squat_ratio)
          expect(criteria).to have_key(:deadlift_ratio)
        end
      end
    end
  end
end
