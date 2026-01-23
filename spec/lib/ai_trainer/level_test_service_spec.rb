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

  # ============================================================
  # AI-BASED PROMOTION EVALUATION TESTS
  # ============================================================

  describe '.evaluate_promotion' do
    it 'delegates to instance method' do
      allow_any_instance_of(described_class).to receive(:evaluate_promotion_readiness)
        .and_return({ eligible: true })

      result = described_class.evaluate_promotion(user: user)
      expect(result[:eligible]).to be true
    end
  end

  describe '#evaluate_promotion_readiness' do
    before do
      allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
        success: true,
        content: '축하합니다! 열심히 하셨네요.',
        model: 'mock'
      })
    end

    context 'without workout data' do
      it 'returns no_data status for all exercises' do
        result = service.evaluate_promotion_readiness

        expect(result[:exercise_results][:bench][:status]).to eq(:no_data)
        expect(result[:exercise_results][:squat][:status]).to eq(:no_data)
        expect(result[:exercise_results][:deadlift][:status]).to eq(:no_data)
      end

      it 'returns not eligible' do
        result = service.evaluate_promotion_readiness
        expect(result[:eligible]).to be false
      end
    end

    context 'with sufficient workout data' do
      let!(:workout_session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      before do
        # Create workout sets that should pass level 4 criteria
        # Level 4 requires: bench 0.8, squat 0.9, deadlift 1.0 ratios
        # For height 175: bench=60, squat=85.5, deadlift=115

        # Bench: 70kg x 5 reps = estimated 1RM ~82kg (passes 60kg requirement)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '벤치프레스', weight: 70, reps: 5, weight_unit: 'kg')

        # Squat: 90kg x 5 reps = estimated 1RM ~105kg (passes 85.5kg requirement)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '스쿼트', weight: 90, reps: 5, weight_unit: 'kg')

        # Deadlift: 120kg x 3 reps = estimated 1RM ~132kg (passes 115kg requirement)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '데드리프트', weight: 120, reps: 3, weight_unit: 'kg')
      end

      it 'returns eligible when all exercises pass' do
        result = service.evaluate_promotion_readiness
        expect(result[:eligible]).to be true
      end

      it 'returns passed status for passing exercises' do
        result = service.evaluate_promotion_readiness

        expect(result[:exercise_results][:bench][:status]).to eq(:passed)
        expect(result[:exercise_results][:squat][:status]).to eq(:passed)
        expect(result[:exercise_results][:deadlift][:status]).to eq(:passed)
      end

      it 'includes estimated 1RM values' do
        result = service.evaluate_promotion_readiness

        expect(result[:estimated_1rms][:bench]).to be > 0
        expect(result[:estimated_1rms][:squat]).to be > 0
        expect(result[:estimated_1rms][:deadlift]).to be > 0
      end

      it 'includes AI feedback' do
        result = service.evaluate_promotion_readiness
        expect(result[:ai_feedback]).to be_present
      end

      it 'returns ready_for_promotion recommendation' do
        result = service.evaluate_promotion_readiness
        expect(result[:recommendation]).to eq(:ready_for_promotion)
      end
    end

    context 'with insufficient strength' do
      let!(:workout_session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      before do
        # Create workout sets that fail level 4 criteria
        # Bench: 40kg x 5 = ~47kg estimated 1RM (fails 60kg requirement)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '벤치프레스', weight: 40, reps: 5, weight_unit: 'kg')
      end

      it 'returns not eligible' do
        result = service.evaluate_promotion_readiness
        expect(result[:eligible]).to be false
      end

      it 'returns failed status for failing exercise' do
        result = service.evaluate_promotion_readiness
        expect(result[:exercise_results][:bench][:status]).to eq(:failed)
      end

      it 'includes gap information' do
        result = service.evaluate_promotion_readiness
        expect(result[:exercise_results][:bench][:gap]).to be > 0
      end

      it 'returns continue_training recommendation' do
        result = service.evaluate_promotion_readiness
        expect(result[:recommendation]).to eq(:continue_training)
      end
    end
  end

  describe '#calculate_estimated_1rms' do
    let!(:workout_session) do
      create(:workout_session, user: user, start_time: 1.week.ago, end_time: 1.week.ago + 1.hour)
    end

    it 'calculates estimated 1RM using Epley formula' do
      # Epley: 1RM = weight * (1 + reps/30)
      # 60kg x 10 reps = 60 * (1 + 10/30) = 60 * 1.333 = 80kg
      create(:workout_set, workout_session: workout_session,
             exercise_name: '벤치프레스', weight: 60, reps: 10, weight_unit: 'kg')

      result = service.calculate_estimated_1rms
      expect(result[:bench]).to be_within(1).of(80)
    end

    it 'uses actual weight for 1 rep' do
      create(:workout_set, workout_session: workout_session,
             exercise_name: '스쿼트', weight: 100, reps: 1, weight_unit: 'kg')

      result = service.calculate_estimated_1rms
      expect(result[:squat]).to eq(100)
    end

    it 'returns best estimated 1RM across multiple sets' do
      # Set 1: 60kg x 8 = 76kg estimated
      create(:workout_set, workout_session: workout_session,
             exercise_name: '벤치프레스', weight: 60, reps: 8, weight_unit: 'kg')

      # Set 2: 70kg x 5 = 81.7kg estimated (best)
      create(:workout_set, workout_session: workout_session,
             exercise_name: '벤치프레스', weight: 70, reps: 5, weight_unit: 'kg')

      result = service.calculate_estimated_1rms
      expect(result[:bench]).to be > 80
    end

    it 'recognizes exercise name variations' do
      create(:workout_set, workout_session: workout_session,
             exercise_name: 'Bench Press', weight: 60, reps: 5, weight_unit: 'kg')

      result = service.calculate_estimated_1rms
      expect(result[:bench]).to be_present
    end

    it 'converts lbs to kg' do
      # 132 lbs x 5 reps = ~60kg x 5 = 70kg estimated
      create(:workout_set, workout_session: workout_session,
             exercise_name: '벤치프레스', weight: 132, reps: 5, weight_unit: 'lbs')

      result = service.calculate_estimated_1rms
      expect(result[:bench]).to be_within(5).of(70)
    end

    it 'only considers workouts within 8 weeks' do
      # Create a user without recent workouts
      user_old = create(:user)
      create(:user_profile, user: user_old, numeric_level: 3, height: 175)

      # Explicitly set created_at to 10 weeks ago (not just start_time)
      old_session = create(:workout_session, user: user_old,
                           start_time: 10.weeks.ago, end_time: 10.weeks.ago + 1.hour)
      old_session.update_column(:created_at, 10.weeks.ago)

      create(:workout_set, workout_session: old_session,
             exercise_name: '벤치프레스', weight: 100, reps: 1, weight_unit: 'kg')

      svc = described_class.new(user: user_old)
      result = svc.calculate_estimated_1rms
      expect(result[:bench]).to be_nil
    end

    it 'returns nil for exercises without data' do
      result = service.calculate_estimated_1rms

      expect(result[:bench]).to be_nil
      expect(result[:squat]).to be_nil
      expect(result[:deadlift]).to be_nil
    end
  end

  describe '#exercise_korean' do
    it 'returns Korean name for bench' do
      expect(service.send(:exercise_korean, :bench)).to eq('벤치프레스')
    end

    it 'returns Korean name for squat' do
      expect(service.send(:exercise_korean, :squat)).to eq('스쿼트')
    end

    it 'returns Korean name for deadlift' do
      expect(service.send(:exercise_korean, :deadlift)).to eq('데드리프트')
    end
  end

  describe 'AI feedback' do
    let!(:workout_session) do
      create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
    end

    before do
      create(:workout_set, workout_session: workout_session,
             exercise_name: '벤치프레스', weight: 70, reps: 5, weight_unit: 'kg')
    end

    context 'when LlmGateway succeeds' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: true,
          content: 'AI 피드백 메시지입니다.',
          model: 'claude-3-5-haiku-20241022'
        })
      end

      it 'returns AI-generated feedback' do
        result = service.evaluate_promotion_readiness
        expect(result[:ai_feedback]).to eq('AI 피드백 메시지입니다.')
      end
    end

    context 'when LlmGateway fails' do
      before do
        allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
          success: false,
          error: 'API error'
        })
      end

      it 'returns default feedback message' do
        result = service.evaluate_promotion_readiness
        expect(result[:ai_feedback]).to be_present
      end
    end
  end
end
