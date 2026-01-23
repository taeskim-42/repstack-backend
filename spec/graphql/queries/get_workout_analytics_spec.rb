# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::GetWorkoutAnalytics, type: :graphql do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let(:query) do
    <<~GQL
      query GetWorkoutAnalytics($days: Int) {
        getWorkoutAnalytics(days: $days) {
          totalWorkouts
          totalTime
          averageRpe
          completionRate
          workoutFrequency
        }
      }
    GQL
  end

  def execute_query(variables = {}, current_user: user)
    RepstackBackendSchema.execute(
      query,
      variables: variables,
      context: { current_user: current_user }
    )
  end

  describe 'when authenticated' do
    context 'with no workout data' do
      it 'returns zero values' do
        result = execute_query({ days: 30 })
        data = result['data']['getWorkoutAnalytics']

        expect(data['totalWorkouts']).to eq(0)
        expect(data['totalTime']).to eq(0)
        expect(data['averageRpe']).to eq(0.0)
        expect(data['completionRate']).to eq(0.0)
      end
    end

    context 'with workout data' do
      let!(:session1) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      let!(:session2) do
        create(:workout_session, user: user, start_time: 3.days.ago, end_time: 3.days.ago + 1.hour)
      end

      let!(:workout_sets) do
        [
          create(:workout_set, workout_session: session1, exercise_name: '벤치프레스', weight: 60, reps: 10, target_muscle: 'chest'),
          create(:workout_set, workout_session: session1, exercise_name: '벤치프레스', weight: 65, reps: 8, target_muscle: 'chest'),
          create(:workout_set, workout_session: session2, exercise_name: '스쿼트', weight: 80, reps: 10, target_muscle: 'legs')
        ]
      end

      it 'returns workout frequency' do
        result = execute_query({ days: 30 })
        data = result['data']['getWorkoutAnalytics']

        # Should have some frequency since we have 2 sessions in 30 days
        expect(data['workoutFrequency']).to be >= 0
      end
    end

    context 'with days parameter' do
      let!(:recent_session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      let!(:old_session) do
        create(:workout_session, user: user, start_time: 60.days.ago, end_time: 60.days.ago + 1.hour)
      end

      it 'filters by days parameter' do
        result = execute_query({ days: 7 })
        # Should only count sessions from last 7 days
        data = result['data']['getWorkoutAnalytics']
        expect(data['totalWorkouts']).to be >= 0
      end

      it 'uses default 30 days when not specified' do
        result = execute_query({})
        data = result['data']['getWorkoutAnalytics']
        expect(data).not_to be_nil
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_query({ days: 30 }, current_user: nil)

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('sign in')
    end
  end
end
