# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::GetUserLevelAssessment, type: :graphql do
  let(:user) { create(:user) }

  before do
    # Ensure profile exists with level assessment
    user.create_user_profile!(
      current_level: 'intermediate',
      fitness_factors: { strength: 7.5, endurance: 6.0, flexibility: 5.0, balance: 6.5, coordination: 7.0 },
      max_lifts: { bench: 80, squat: 100, deadlift: 120 },
      level_assessed_at: 10.days.ago
    )
  end

  let(:query) do
    <<~GQL
      query GetUserLevelAssessment {
        getUserLevelAssessment {
          userId
          level
          fitnessFactors {
            strength
            endurance
            flexibility
            balance
            coordination
          }
          maxLifts
          assessedAt
          validUntil
        }
      }
    GQL
  end

  describe 'when authenticated' do
    context 'with level assessment' do
      it 'returns assessment data' do
        result = execute_graphql(query: query, context: { current_user: user })

        data = result['data']['getUserLevelAssessment']
        expect(data['userId']).to eq(user.id.to_s)
        expect(data['level']).to eq('INTERMEDIATE')
        expect(data['fitnessFactors']['strength']).to eq(7.5)
        expect(data['maxLifts']).to include('bench' => 80)
        expect(data['assessedAt']).to match(/^\d{4}-\d{2}-\d{2}/)
        expect(data['validUntil']).to match(/^\d{4}-\d{2}-\d{2}/)
      end
    end

    context 'without level assessment' do
      it 'returns nil' do
        user_no_assessment = create(:user)
        user_no_assessment.create_user_profile!(level_assessed_at: nil)

        result = execute_graphql(query: query, context: { current_user: user_no_assessment })

        expect(result['data']['getUserLevelAssessment']).to be_nil
      end
    end

    context 'without user profile' do
      it 'returns nil' do
        user_no_profile = create(:user)

        result = execute_graphql(query: query, context: { current_user: user_no_profile })

        expect(result['data']['getUserLevelAssessment']).to be_nil
      end
    end

    context 'with default level' do
      it 'returns BEGINNER as default level' do
        user_default = create(:user)
        user_default.create_user_profile!(current_level: nil, level_assessed_at: 5.days.ago)

        result = execute_graphql(query: query, context: { current_user: user_default })

        data = result['data']['getUserLevelAssessment']
        expect(data['level']).to eq('BEGINNER')
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
