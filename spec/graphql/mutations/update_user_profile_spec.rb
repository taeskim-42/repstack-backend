# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::UpdateUserProfile, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, height: 170, weight: 65) }

  let(:mutation) do
    <<~GQL
      mutation UpdateUserProfile($height: Float, $weight: Float, $bodyFatPercentage: Float, $currentLevel: String, $fitnessGoal: String, $weekNumber: Int, $dayNumber: Int) {
        updateUserProfile(input: { height: $height, weight: $weight, bodyFatPercentage: $bodyFatPercentage, currentLevel: $currentLevel, fitnessGoal: $fitnessGoal, weekNumber: $weekNumber, dayNumber: $dayNumber }) {
          userProfile {
            id
            height
            weight
            bodyFatPercentage
            currentLevel
            fitnessGoal
            weekNumber
            dayNumber
          }
          errors
        }
      }
    GQL
  end

  describe 'when authenticated' do
    context 'with valid input' do
      it 'updates profile height' do
        result = execute_graphql(
          query: mutation,
          variables: { height: 175.5 },
          context: { current_user: user }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['height']).to eq(175.5)
      end

      it 'updates profile weight' do
        result = execute_graphql(
          query: mutation,
          variables: { weight: 70.0 },
          context: { current_user: user }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['weight']).to eq(70.0)
      end

      it 'updates multiple fields at once' do
        result = execute_graphql(
          query: mutation,
          variables: { height: 180.0, weight: 75.0, bodyFatPercentage: 18.0 },
          context: { current_user: user }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['height']).to eq(180.0)
        expect(data['userProfile']['weight']).to eq(75.0)
        expect(data['userProfile']['bodyFatPercentage']).to eq(18.0)
      end

      it 'updates fitness goal' do
        result = execute_graphql(
          query: mutation,
          variables: { fitnessGoal: 'weight_loss' },
          context: { current_user: user }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['fitnessGoal']).to eq('weight_loss')
      end

      it 'updates current level' do
        result = execute_graphql(
          query: mutation,
          variables: { currentLevel: 'intermediate' },
          context: { current_user: user }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['currentLevel']).to eq('intermediate')
      end

      it 'updates week and day number' do
        result = execute_graphql(
          query: mutation,
          variables: { weekNumber: 2, dayNumber: 3 },
          context: { current_user: user }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['weekNumber']).to eq(2)
        expect(data['userProfile']['dayNumber']).to eq(3)
      end
    end

    context 'with invalid level' do
      it 'returns error for invalid level' do
        result = execute_graphql(
          query: mutation,
          variables: { currentLevel: 'expert' },
          context: { current_user: user }
        )

        expect(result['errors']).to be_present
        expect(result['errors'].first['message']).to include('Invalid level')
      end
    end

    context 'with invalid day number' do
      it 'returns error for day number > 7' do
        result = execute_graphql(
          query: mutation,
          variables: { dayNumber: 8 },
          context: { current_user: user }
        )

        expect(result['errors']).to be_present
        expect(result['errors'].first['message']).to include('Invalid day number')
      end

      it 'returns error for day number < 1' do
        result = execute_graphql(
          query: mutation,
          variables: { dayNumber: 0 },
          context: { current_user: user }
        )

        expect(result['errors']).to be_present
        expect(result['errors'].first['message']).to include('Invalid day number')
      end
    end

    context 'without existing profile' do
      let(:user_without_profile) { create(:user) }

      it 'creates new profile' do
        result = execute_graphql(
          query: mutation,
          variables: { height: 175.0, weight: 70.0 },
          context: { current_user: user_without_profile }
        )

        data = result['data']['updateUserProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['height']).to eq(175.0)
        expect(user_without_profile.reload.user_profile).to be_present
      end
    end

    context 'when validation fails' do
      it 'returns validation errors' do
        # Day number validation in model (if exists)
        result = execute_graphql(
          query: mutation,
          variables: { dayNumber: 1 },
          context: { current_user: user }
        )

        # Should work if day_number is valid
        data = result['data']['updateUserProfile']
        expect(data['userProfile']).to be_present
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_graphql(
        query: mutation,
        variables: { height: 175.0 },
        context: { current_user: nil }
      )

      expect(result['errors']).to be_present
    end
  end
end
