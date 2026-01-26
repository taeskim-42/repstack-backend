# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::RoutineGenerator do
  let(:user) { create(:user) }
  let!(:user_profile) do
    create(:user_profile, user: user, numeric_level: 1, height: 175, weight: 70,
           onboarding_completed_at: Time.current)
  end
  let(:generator) { described_class.new(user: user, day_of_week: 1, week: 1) }

  describe '#initialize' do
    it 'sets default values' do
      expect(generator.user).to eq(user)
      expect(generator.level).to eq(1)
      expect(generator.condition_score).to eq(3.0)
    end

    it 'converts Sunday to Monday' do
      allow(Time).to receive(:current).and_return(Time.new(2026, 1, 25)) # Sunday
      gen = described_class.new(user: user)
      expect(gen.day_of_week).to eq(1)
    end

    it 'converts weekend days to Friday' do
      allow(Time).to receive(:current).and_return(Time.new(2026, 1, 24)) # Saturday
      gen = described_class.new(user: user)
      expect(gen.day_of_week).to eq(5)
    end

    it 'accepts explicit day_of_week' do
      gen = described_class.new(user: user, day_of_week: 3)
      expect(gen.day_of_week).to eq(3)
    end

    it 'accepts explicit week' do
      gen = described_class.new(user: user, week: 3)
      expect(gen.week).to eq(3)
    end

    it 'calculates current week from onboarding date' do
      # User onboarded 2 weeks ago
      user_profile.update!(onboarding_completed_at: 2.weeks.ago)
      gen = described_class.new(user: user.reload)
      expect(gen.week).to eq(3) # 0 weeks = week 1, 2 weeks = week 3
    end
  end

  describe '#with_condition' do
    let(:condition_inputs) do
      { sleep: 4, fatigue: 2, stress: 2, soreness: 1, motivation: 5 }
    end

    it 'sets condition inputs' do
      generator.with_condition(condition_inputs)
      expect(generator.condition_inputs).to eq(condition_inputs)
    end

    it 'calculates condition score' do
      generator.with_condition(condition_inputs)
      expect(generator.condition_score).to be > 0
    end

    it 'returns self for chaining' do
      result = generator.with_condition(condition_inputs)
      expect(result).to eq(generator)
    end
  end

  describe '#with_feedbacks' do
    let(:feedbacks) { [double(created_at: 1.day.ago, feedback: 'test', suggestions: [])] }

    it 'sets recent feedbacks' do
      generator.with_feedbacks(feedbacks)
      expect(generator.recent_feedbacks).to eq(feedbacks)
    end

    it 'handles nil feedbacks' do
      generator.with_feedbacks(nil)
      expect(generator.recent_feedbacks).to eq([])
    end

    it 'returns self for chaining' do
      result = generator.with_feedbacks(feedbacks)
      expect(result).to eq(generator)
    end
  end

  describe '#generate' do
    context 'with valid workout program' do
      it 'returns routine from WorkoutPrograms' do
        result = generator.generate
        expect(result[:routine_id]).to start_with('RT-')
        expect(result[:exercises]).to be_an(Array)
        expect(result[:exercises].length).to be > 0
      end

      it 'includes correct training type for day 1' do
        result = generator.generate
        expect(result[:training_type]).to eq('strength')
        expect(result[:training_type_korean]).to eq('근력')
      end

      it 'includes week information' do
        result = generator.generate
        expect(result[:week]).to eq(1)
      end

      it 'includes exercises from beginner program' do
        result = generator.generate
        exercise_names = result[:exercises].map { |e| e[:exercise_name] }
        expect(exercise_names).to include('BPM 푸시업')
        expect(exercise_names).to include('BPM 9칸 턱걸이')
        expect(exercise_names).to include('BPM 기둥 스쿼트')
      end
    end

    context 'with intermediate level user' do
      let!(:user_profile) do
        create(:user_profile, user: user, numeric_level: 4, height: 175, weight: 70,
               onboarding_completed_at: Time.current)
      end
      let(:generator) { described_class.new(user: user.reload, day_of_week: 1, week: 1) }

      it 'returns intermediate program exercises' do
        result = generator.generate
        exercise_names = result[:exercises].map { |e| e[:exercise_name] }
        expect(exercise_names).to include('벤치프레스')
        expect(exercise_names).to include('렛풀다운')
      end
    end

    context 'with different days' do
      it 'returns muscular_endurance for day 2' do
        gen = described_class.new(user: user, day_of_week: 2, week: 1)
        result = gen.generate
        expect(result[:training_type]).to eq('muscular_endurance')
      end

      it 'returns cardiovascular for day 5' do
        gen = described_class.new(user: user, day_of_week: 5, week: 1)
        result = gen.generate
        expect(result[:training_type]).to eq('cardiovascular')
      end
    end
  end

  describe 'condition-based adjustments' do
    context 'with poor condition' do
      before do
        generator.with_condition(sleep: 1, fatigue: 5, stress: 5, soreness: 5, motivation: 1)
      end

      it 'reduces volume modifier' do
        result = generator.generate
        expect(result[:condition][:volume_modifier]).to be < 1.0
      end

      it 'adjusts sets and reps downward' do
        result = generator.generate
        # Original: 3 sets x 10 reps, with 70% volume should be ~2 sets x ~8 reps
        first_exercise = result[:exercises].first
        expect(first_exercise[:sets]).to be < 3
      end
    end

    context 'with excellent condition' do
      before do
        generator.with_condition(sleep: 5, fatigue: 1, stress: 1, soreness: 1, motivation: 5)
      end

      it 'increases volume modifier' do
        result = generator.generate
        expect(result[:condition][:volume_modifier]).to be >= 1.0
      end

      it 'adjusts target_total_reps upward for endurance exercises' do
        gen = described_class.new(user: user, day_of_week: 2, week: 1) # Muscular endurance day
          .with_condition(sleep: 5, fatigue: 1, stress: 1, soreness: 1, motivation: 5)
        result = gen.generate
        # Original target: 100 reps, with 110% should be 110 reps
        endurance_exercise = result[:exercises].find { |e| e[:target_total_reps] }
        expect(endurance_exercise[:target_total_reps]).to be >= 100
      end
    end
  end

  describe 'week progression' do
    it 'week 1 has lower volume than week 4' do
      gen_week1 = described_class.new(user: user, day_of_week: 1, week: 1)
      gen_week4 = described_class.new(user: user, day_of_week: 1, week: 4)

      result1 = gen_week1.generate
      result4 = gen_week4.generate

      # Week 4 should have higher reps/sets
      week1_total = result1[:exercises].sum { |e| (e[:sets] || 0) * (e[:reps] || 0) + (e[:target_total_reps] || 0) }
      week4_total = result4[:exercises].sum { |e| (e[:sets] || 0) * (e[:reps] || 0) + (e[:target_total_reps] || 0) }

      expect(week4_total).to be > week1_total
    end
  end

  describe '#generate_routine_id' do
    it 'generates unique ID' do
      id1 = generator.send(:generate_routine_id)
      id2 = generator.send(:generate_routine_id)
      expect(id1).not_to eq(id2)
    end

    it 'includes level, week, and day info' do
      id = generator.send(:generate_routine_id)
      expect(id).to start_with('RT-')
      expect(id).to include('W1')
      expect(id).to include('D1')
    end
  end

  describe '#calculate_rest_seconds' do
    it 'returns 90 seconds for strength training' do
      result = generator.send(:calculate_rest_seconds, :strength)
      expect(result).to eq(90)
    end

    it 'returns 60 seconds for muscular endurance' do
      result = generator.send(:calculate_rest_seconds, :muscular_endurance)
      expect(result).to eq(60)
    end

    it 'returns 10 seconds for cardiovascular (tabata)' do
      result = generator.send(:calculate_rest_seconds, :cardiovascular)
      expect(result).to eq(10)
    end
  end

  describe '#format_rom' do
    it 'formats :full correctly' do
      expect(generator.send(:format_rom, :full)).to eq('full')
    end

    it 'formats :medium correctly' do
      expect(generator.send(:format_rom, :medium)).to eq('medium')
    end

    it 'formats :short correctly' do
      expect(generator.send(:format_rom, :short)).to eq('short')
    end

    it 'defaults to full for unknown ROM' do
      expect(generator.send(:format_rom, :unknown)).to eq('full')
    end
  end

  describe '#default_instruction' do
    it 'returns strength instruction for strength training' do
      result = generator.send(:default_instruction, :strength)
      expect(result).to include('BPM')
    end

    it 'returns endurance instruction for muscular_endurance' do
      result = generator.send(:default_instruction, :muscular_endurance)
      expect(result).to include('목표 횟수')
    end

    it 'returns tabata instruction for cardiovascular' do
      result = generator.send(:default_instruction, :cardiovascular)
      expect(result).to include('20초')
    end
  end

  describe '#estimate_duration' do
    it 'estimates shorter time for cardiovascular' do
      exercises = [{ name: 'test' }] * 4
      cardio_duration = generator.send(:estimate_duration, exercises, :cardiovascular)
      strength_duration = generator.send(:estimate_duration, exercises, :strength)
      expect(cardio_duration).to be < strength_duration
    end
  end

  describe 'level-based configurations' do
    context 'with level 8 user (max)' do
      let!(:user_profile) do
        create(:user_profile, user: user, numeric_level: 8, height: 175, weight: 70,
               onboarding_completed_at: Time.current)
      end
      let(:generator) { described_class.new(user: user.reload, day_of_week: 1, week: 1) }

      it 'returns advanced tier' do
        result = generator.generate
        expect(result[:tier]).to eq('advanced')
        expect(result[:tier_korean]).to eq('고급')
      end
    end

    context 'with level 1 user' do
      it 'returns beginner tier' do
        result = generator.generate
        expect(result[:tier]).to eq('beginner')
        expect(result[:tier_korean]).to eq('초급')
      end
    end
  end

  describe 'notes generation' do
    it 'includes week and training type info' do
      result = generator.generate
      notes = result[:notes]
      expect(notes.any? { |n| n.include?('1주차') }).to be true
      expect(notes.any? { |n| n.include?('근력') }).to be true
    end

    context 'with poor condition' do
      before do
        generator.with_condition(sleep: 1, fatigue: 5, stress: 5)
      end

      it 'includes condition adjustment note' do
        result = generator.generate
        notes = result[:notes]
        expect(notes.any? { |n| n.include?('컨디션') }).to be true
      end
    end
  end

  describe 'error handling' do
    context 'when WorkoutPrograms returns nil' do
      before do
        allow(AiTrainer::WorkoutPrograms).to receive(:get_workout).and_return(nil)
      end

      it 'returns error response' do
        result = generator.generate
        expect(result[:success]).to be false
        expect(result[:error]).to include('찾을 수 없습니다')
      end
    end
  end
end
