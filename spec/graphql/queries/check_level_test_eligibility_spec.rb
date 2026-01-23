# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::CheckLevelTestEligibility, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user) }

  let(:query) do
    <<~GQL
      query CheckLevelTestEligibility {
        checkLevelTestEligibility {
          eligible
          reason
          remainingWorkouts
          daysUntilEligible
        }
      }
    GQL
  end

  describe 'when authenticated' do
    context 'when eligible' do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: true,
          reason: '승급 테스트를 볼 수 있습니다.',
          current_workouts: 20,
          required_workouts: 20,
          days_until_eligible: 0
        })
      end

      it 'returns eligible status' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkLevelTestEligibility']
        expect(data['eligible']).to be true
        expect(data['reason']).to include('승급 테스트')
      end
    end

    context 'when not enough workouts' do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: false,
          reason: '20회 더 운동하면 승급 테스트를 볼 수 있습니다.',
          current_workouts: 0,
          required_workouts: 20,
          days_until_eligible: 0
        })
      end

      it 'returns ineligible with remaining workouts' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkLevelTestEligibility']
        expect(data['eligible']).to be false
        expect(data['remainingWorkouts']).to eq(20)
      end
    end

    context 'when in cooldown period' do
      before do
        allow(AiTrainer).to receive(:check_test_eligibility).and_return({
          eligible: false,
          reason: '3일 후에 다시 테스트할 수 있습니다.',
          remaining_workouts: 0,
          days_until_eligible: 3
        })
      end

      it 'returns ineligible with days until eligible' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['checkLevelTestEligibility']
        expect(data['eligible']).to be false
        expect(data['daysUntilEligible']).to eq(3)
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_graphql(query: query, context: { current_user: nil })

      expect(result['errors']).to be_present
    end
  end
end
