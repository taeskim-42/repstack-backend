# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::UpdateProfile, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, height: 170, weight: 65) }

  let(:mutation) do
    <<~GQL
      mutation UpdateProfile($profileInput: UserProfileInput!) {
        updateProfile(input: { profileInput: $profileInput }) {
          userProfile {
            id
            height
            weight
            bodyFatPercentage
            fitnessGoal
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
          variables: { profileInput: { height: 175.0 } },
          context: { current_user: user }
        )

        data = result['data']['updateProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['height']).to eq(175.0)
      end

      it 'updates profile weight' do
        result = execute_graphql(
          query: mutation,
          variables: { profileInput: { weight: 70.0 } },
          context: { current_user: user }
        )

        data = result['data']['updateProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['weight']).to eq(70.0)
      end

      it 'updates multiple fields at once' do
        result = execute_graphql(
          query: mutation,
          variables: { profileInput: { height: 180.0, weight: 75.0, bodyFatPercentage: 18.0 } },
          context: { current_user: user }
        )

        data = result['data']['updateProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['height']).to eq(180.0)
        expect(data['userProfile']['weight']).to eq(75.0)
        expect(data['userProfile']['bodyFatPercentage']).to eq(18.0)
      end

      it 'updates fitness goal' do
        result = execute_graphql(
          query: mutation,
          variables: { profileInput: { fitnessGoal: 'weight_loss' } },
          context: { current_user: user }
        )

        data = result['data']['updateProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['fitnessGoal']).to eq('weight_loss')
      end
    end

    context 'without existing profile' do
      let(:user_without_profile) { create(:user) }

      it 'creates new profile' do
        result = execute_graphql(
          query: mutation,
          variables: { profileInput: { height: 175.0, weight: 70.0 } },
          context: { current_user: user_without_profile }
        )

        data = result['data']['updateProfile']
        expect(data['errors']).to be_empty
        expect(data['userProfile']['height']).to eq(175.0)
        expect(user_without_profile.reload.user_profile).to be_present
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_graphql(
        query: mutation,
        variables: { profileInput: { height: 175.0 } },
        context: { current_user: nil }
      )

      expect(result['errors']).to be_present
    end
  end
end
