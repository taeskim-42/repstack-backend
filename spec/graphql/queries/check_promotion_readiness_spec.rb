# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::CheckPromotionReadiness, type: :request do
  include GraphQL::TestHelpers

  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }

  let(:query) do
    <<~GQL
      query CheckPromotionReadiness {
        checkPromotionReadiness {
          eligible
          currentLevel
          targetLevel
          estimated1rms {
            bench
            squat
            deadlift
          }
          required1rms {
            bench
            squat
            deadlift
          }
          exerciseResults {
            exerciseType
            status
            estimated1rm
            required
            surplus
            gap
            message
          }
          aiFeedback
          recommendation
        }
      }
    GQL
  end

  before do
    allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
      success: true,
      content: '열심히 하셨네요!',
      model: 'mock'
    })
  end

  describe 'when authenticated' do
    context 'without workout data' do
      it 'returns not eligible' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        expect(data['eligible']).to be false
        expect(data['recommendation']).to eq('continue_training')
      end

      it 'returns no_data status for all exercises' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        statuses = data['exerciseResults'].map { |e| e['status'] }
        expect(statuses).to all(eq('no_data'))
      end

      it 'returns required 1RMs based on height' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        # Level 3 -> 4: bench 0.8, squat 0.9, deadlift 1.0
        # Height 175: bench = (175-100)*0.8 = 60, squat = (175-100+20)*0.9 = 85.5, deadlift = (175-100+40)*1.0 = 115
        expect(data['required1rms']['bench']).to be_within(1).of(60)
        expect(data['required1rms']['squat']).to be_within(1).of(85.5)
        expect(data['required1rms']['deadlift']).to be_within(1).of(115)
      end
    end

    context 'with sufficient workout data' do
      let!(:workout_session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      before do
        # Create workout sets that meet level 4 criteria
        # Bench: 70kg x 5 reps = ~82kg estimated 1RM (passes 60kg)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '벤치프레스', weight: 70, reps: 5, weight_unit: 'kg')

        # Squat: 90kg x 5 reps = ~105kg estimated 1RM (passes 85.5kg)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '스쿼트', weight: 90, reps: 5, weight_unit: 'kg')

        # Deadlift: 120kg x 3 reps = ~132kg estimated 1RM (passes 115kg)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '데드리프트', weight: 120, reps: 3, weight_unit: 'kg')
      end

      it 'returns eligible' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        expect(data['eligible']).to be true
        expect(data['recommendation']).to eq('ready_for_promotion')
      end

      it 'returns estimated 1RMs' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        expect(data['estimated1rms']['bench']).to be > 0
        expect(data['estimated1rms']['squat']).to be > 0
        expect(data['estimated1rms']['deadlift']).to be > 0
      end

      it 'returns passed status for all exercises' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        statuses = data['exerciseResults'].map { |e| e['status'] }
        expect(statuses).to all(eq('passed'))
      end

      it 'returns surplus for passing exercises' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        bench_result = data['exerciseResults'].find { |e| e['exerciseType'] == 'bench' }
        expect(bench_result['surplus']).to be > 0
      end

      it 'returns AI feedback' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        expect(data['aiFeedback']).to be_present
      end
    end

    context 'with partial workout data' do
      let!(:workout_session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      before do
        # Only bench press data - squat and deadlift missing
        create(:workout_set, workout_session: workout_session,
               exercise_name: '벤치프레스', weight: 70, reps: 5, weight_unit: 'kg')
      end

      it 'returns not eligible' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        expect(data['eligible']).to be false
      end

      it 'returns mixed statuses' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        bench_result = data['exerciseResults'].find { |e| e['exerciseType'] == 'bench' }
        squat_result = data['exerciseResults'].find { |e| e['exerciseType'] == 'squat' }

        expect(bench_result['status']).to eq('passed')
        expect(squat_result['status']).to eq('no_data')
      end
    end

    context 'with insufficient strength' do
      let!(:workout_session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      before do
        # Bench: 40kg x 5 = ~47kg (fails 60kg requirement)
        create(:workout_set, workout_session: workout_session,
               exercise_name: '벤치프레스', weight: 40, reps: 5, weight_unit: 'kg')
      end

      it 'returns failed status with gap' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        bench_result = data['exerciseResults'].find { |e| e['exerciseType'] == 'bench' }

        expect(bench_result['status']).to eq('failed')
        expect(bench_result['gap']).to be > 0
      end
    end

    context 'at max level' do
      before { profile.update!(numeric_level: 8) }

      it 'returns current level info' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkPromotionReadiness']
        expect(data['currentLevel']).to eq(8)
        expect(data['targetLevel']).to eq(8) # Can't go higher
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns login required' do
      result = execute_graphql(query: query, context: { current_user: nil })

      data = result['data']['checkPromotionReadiness']
      expect(data['eligible']).to be false
      expect(data['recommendation']).to eq('login_required')
      expect(data['aiFeedback']).to include('로그인')
    end
  end

  describe 'when user has no profile' do
    let(:user_without_profile) { create(:user) }

    it 'returns profile required' do
      result = execute_graphql(query: query, context: { current_user: user_without_profile })

      data = result['data']['checkPromotionReadiness']
      expect(data['eligible']).to be false
      expect(data['recommendation']).to eq('profile_required')
      expect(data['aiFeedback']).to include('프로필')
    end
  end
end
