# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::LevelTestService do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }
  let(:service) { described_class.new(user: user) }

  describe '#initialize' do
    it 'sets user' do
      expect(service.user).to eq(user)
    end

    it 'sets current level from profile' do
      expect(service.current_level).to eq(3)
    end

    it 'defaults to level 1 when no profile' do
      user_without_profile = create(:user)
      svc = described_class.new(user: user_without_profile)
      expect(svc.current_level).to eq(1)
    end
  end

  describe '#generate_test' do
    let(:result) { service.generate_test }

    it 'returns test structure' do
      expect(result).to include(
        :test_id,
        :current_level,
        :target_level,
        :test_type,
        :criteria,
        :exercises,
        :instructions,
        :time_limit_minutes,
        :pass_conditions
      )
    end

    it 'sets current level' do
      expect(result[:current_level]).to eq(3)
    end

    it 'sets target level as next level' do
      expect(result[:target_level]).to eq(4)
    end

    it 'includes exercises' do
      expect(result[:exercises]).to be_an(Array)
      expect(result[:exercises].length).to eq(3)
    end

    it 'includes bench press exercise' do
      bench = result[:exercises].find { |e| e[:exercise_name] == '벤치프레스' }
      expect(bench).not_to be_nil
      expect(bench[:target_reps]).to eq(1)
    end

    it 'includes squat exercise' do
      squat = result[:exercises].find { |e| e[:exercise_name] == '스쿼트' }
      expect(squat).not_to be_nil
    end

    it 'includes deadlift exercise' do
      deadlift = result[:exercises].find { |e| e[:exercise_name] == '데드리프트' }
      expect(deadlift).not_to be_nil
    end

    it 'generates unique test id' do
      id1 = service.generate_test[:test_id]
      id2 = service.generate_test[:test_id]
      expect(id1).not_to eq(id2)
    end

    it 'sets time limit' do
      expect(result[:time_limit_minutes]).to eq(30)
    end
  end

  describe '#evaluate_results' do
    let(:test_results) do
      {
        test_id: 'LT-3-123456789-abc12345',
        exercises: [
          { exercise_type: 'bench', weight_kg: 80, reps: 1 },
          { exercise_type: 'squat', weight_kg: 100, reps: 1 },
          { exercise_type: 'deadlift', weight_kg: 120, reps: 1 }
        ]
      }
    end

    it 'returns evaluation structure' do
      result = service.evaluate_results(test_results)
      expect(result).to include(
        :test_id,
        :passed,
        :new_level,
        :results,
        :feedback,
        :next_steps
      )
    end

    context 'when all exercises pass' do
      let(:test_results) do
        {
          test_id: 'LT-3-123456789-abc12345',
          exercises: [
            { exercise_type: 'bench', weight_kg: 200, reps: 1 },
            { exercise_type: 'squat', weight_kg: 250, reps: 1 },
            { exercise_type: 'deadlift', weight_kg: 300, reps: 1 }
          ]
        }
      end

      it 'marks test as passed' do
        result = service.evaluate_results(test_results)
        expect(result[:passed]).to be true
      end

      it 'sets new level to next level' do
        result = service.evaluate_results(test_results)
        expect(result[:new_level]).to eq(4)
      end

      it 'returns congratulations feedback' do
        result = service.evaluate_results(test_results)
        expect(result[:feedback].first).to include('축하')
      end
    end

    context 'when some exercises fail' do
      let(:test_results) do
        {
          test_id: 'LT-3-123456789-abc12345',
          exercises: [
            { exercise_type: 'bench', weight_kg: 10, reps: 1 }, # Too low
            { exercise_type: 'squat', weight_kg: 200, reps: 1 },
            { exercise_type: 'deadlift', weight_kg: 200, reps: 1 }
          ]
        }
      end

      it 'marks test as failed' do
        result = service.evaluate_results(test_results)
        expect(result[:passed]).to be false
      end

      it 'keeps current level' do
        result = service.evaluate_results(test_results)
        expect(result[:new_level]).to eq(3)
      end

      it 'returns failure feedback' do
        result = service.evaluate_results(test_results)
        expect(result[:feedback].first).to include('아쉽')
      end

      it 'includes failed exercises in feedback' do
        result = service.evaluate_results(test_results)
        expect(result[:feedback].join).to include('부족')
      end
    end
  end

  describe '#eligible_for_test?' do
    context 'without profile' do
      let(:user_without_profile) { create(:user) }
      let(:service) { described_class.new(user: user_without_profile) }

      it 'returns ineligible' do
        result = service.eligible_for_test?
        expect(result[:eligible]).to be false
        expect(result[:reason]).to include('프로필')
      end
    end

    context 'when never taken a test before' do
      it 'returns eligible without workout requirement' do
        result = service.eligible_for_test?
        expect(result[:eligible]).to be true
      end
    end

    context 'with insufficient workouts' do
      before do
        user_profile.update!(last_level_test_at: 10.days.ago)
        # No workouts completed
      end

      it 'returns ineligible' do
        result = service.eligible_for_test?
        expect(result[:eligible]).to be false
        expect(result[:reason]).to include('운동하면')
      end
    end

    context 'within cooldown period' do
      before do
        user_profile.update!(last_level_test_at: 3.days.ago)
        # Create enough workouts
        25.times do
          session = create(:workout_session, user: user, start_time: 1.hour.ago, end_time: Time.current)
        end
      end

      it 'returns ineligible' do
        result = service.eligible_for_test?
        expect(result[:eligible]).to be false
        expect(result[:reason]).to include('7일')
      end

      it 'includes days remaining' do
        result = service.eligible_for_test?
        expect(result[:days_until_eligible]).to be > 0
      end
    end

    context 'at max level' do
      before do
        user_profile.update!(numeric_level: 8)
      end

      let(:service) { described_class.new(user: user.reload) }

      it 'returns ineligible' do
        result = service.eligible_for_test?
        expect(result[:eligible]).to be false
        expect(result[:reason]).to include('최고 레벨')
      end
    end

    context 'when eligible' do
      before do
        user_profile.update!(last_level_test_at: 10.days.ago)
        # Create enough workouts
        25.times do
          create(:workout_session, user: user, start_time: 1.hour.ago, end_time: Time.current)
        end
      end

      it 'returns eligible' do
        result = service.eligible_for_test?
        expect(result[:eligible]).to be true
      end

      it 'includes level info' do
        result = service.eligible_for_test?
        expect(result[:current_level]).to eq(3)
        expect(result[:target_level]).to eq(4)
      end
    end
  end

  describe '#determine_test_type' do
    it 'returns form_test for beginner tier' do
      # Level 1 -> Level 2 (beginner)
      user_profile.update!(numeric_level: 1)
      svc = described_class.new(user: user.reload)
      expect(svc.send(:determine_test_type)).to eq(:form_test)
    end

    it 'returns strength_test for intermediate tier' do
      # Level 3 -> Level 4 (intermediate)
      expect(service.send(:determine_test_type)).to eq(:strength_test)
    end

    it 'returns comprehensive_test for advanced tier' do
      # Level 5 -> Level 6 (advanced)
      user_profile.update!(numeric_level: 5)
      svc = described_class.new(user: user.reload)
      expect(svc.send(:determine_test_type)).to eq(:comprehensive_test)
    end
  end

  describe '#minimum_workouts_for_test' do
    it 'returns 10 for levels 1-2' do
      user_profile.update!(numeric_level: 1)
      svc = described_class.new(user: user.reload)
      expect(svc.send(:minimum_workouts_for_test)).to eq(10)
    end

    it 'returns 20 for levels 3-5' do
      expect(service.send(:minimum_workouts_for_test)).to eq(20)
    end

    it 'returns 30 for levels 6-7' do
      user_profile.update!(numeric_level: 6)
      svc = described_class.new(user: user.reload)
      expect(svc.send(:minimum_workouts_for_test)).to eq(30)
    end
  end

  describe '#calculate_required_weight' do
    let(:criteria) { { bench_ratio: 0.8, squat_ratio: 1.0, deadlift_ratio: 1.2 } }
    let(:height) { 175 }

    it 'calculates bench press weight' do
      result = service.send(:calculate_required_weight, criteria, :bench, height)
      # (175 - 100) * 0.8 = 60
      expect(result).to eq(60.0)
    end

    it 'calculates squat weight' do
      result = service.send(:calculate_required_weight, criteria, :squat, height)
      # (175 - 100 + 20) * 1.0 = 95
      expect(result).to eq(95.0)
    end

    it 'calculates deadlift weight' do
      result = service.send(:calculate_required_weight, criteria, :deadlift, height)
      # (175 - 100 + 40) * 1.2 = 138
      expect(result).to eq(138.0)
    end
  end

  describe '#find_grade_for_level' do
    it 'finds correct grade for level' do
      result = service.send(:find_grade_for_level, 3)
      expect(result).to be_a(String)
    end
  end

  describe '#generate_feedback' do
    it 'returns congratulations for passed test' do
      result = service.send(:generate_feedback, true, [])
      expect(result.first).to include('축하')
    end

    it 'returns encouragement for failed test' do
      failed = [ { exercise: :bench, gap: 10.0 } ]
      result = service.send(:generate_feedback, false, failed)
      expect(result.first).to include('아쉽')
    end

    it 'includes gap info for failed exercises' do
      failed = [ { exercise: :bench, gap: 10.5 } ]
      result = service.send(:generate_feedback, false, failed)
      expect(result.join).to include('10.5kg 부족')
    end
  end

  describe '#generate_next_steps' do
    it 'returns promotion steps for passed test' do
      result = service.send(:generate_next_steps, true, [])
      expect(result.first).to include('새로운 레벨')
    end

    it 'returns improvement steps for failed test' do
      failed = [ { exercise: :bench } ]
      result = service.send(:generate_next_steps, false, failed)
      expect(result.join).to include('가슴')
    end

    it 'suggests squat improvement' do
      failed = [ { exercise: :squat } ]
      result = service.send(:generate_next_steps, false, failed)
      expect(result.join).to include('하체')
    end

    it 'suggests deadlift improvement' do
      failed = [ { exercise: :deadlift } ]
      result = service.send(:generate_next_steps, false, failed)
      expect(result.join).to include('등')
    end
  end
end
