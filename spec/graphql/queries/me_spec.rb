# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::Me, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) do
    create(:user_profile, user: user,
           height: 175, weight: 70, body_fat_percentage: 15.0,
           numeric_level: 3, fitness_goal: 'muscle_gain',
           program_start_date: 30.days.ago,
           level_assessed_at: 7.days.ago,
           last_level_test_at: 14.days.ago)
  end

  let(:query) do
    <<~GQL
      query Me {
        me {
          id
          email
          name
          createdAt
          updatedAt
          hasActiveWorkout
          totalWorkoutSessions
          userProfile {
            id
            height
            weight
            bodyFatPercentage
            currentLevel
            weekNumber
            dayNumber
            fitnessGoal
            programStartDate
            numericLevel
            fitnessFactors
            maxLifts
            totalWorkoutsCompleted
            levelAssessedAt
            lastLevelTestAt
            createdAt
            updatedAt
            bmi
            bmiCategory
            daysSinceStart
          }
        }
      }
    GQL
  end

  describe 'when authenticated' do
    it 'returns current user info' do
      result = execute_graphql(query: query, context: { current_user: user })

      data = result['data']['me']
      expect(data['id']).to eq(user.id.to_s)
      expect(data['email']).to eq(user.email)
    end

    it 'returns user profile with computed fields' do
      result = execute_graphql(query: query, context: { current_user: user })

      profile_data = result['data']['me']['userProfile']
      expect(profile_data['height']).to eq(175.0)
      expect(profile_data['weight']).to eq(70.0)
      expect(profile_data['bmi']).to be_present
      expect(profile_data['bmiCategory']).to be_present
      expect(profile_data['daysSinceStart']).to be >= 0
    end

    it 'returns profile dates in ISO8601 format' do
      result = execute_graphql(query: query, context: { current_user: user })

      profile_data = result['data']['me']['userProfile']
      expect(profile_data['programStartDate']).to match(/^\d{4}-\d{2}-\d{2}/)
      expect(profile_data['levelAssessedAt']).to match(/^\d{4}-\d{2}-\d{2}/)
      expect(profile_data['lastLevelTestAt']).to match(/^\d{4}-\d{2}-\d{2}/)
      expect(profile_data['createdAt']).to match(/^\d{4}-\d{2}-\d{2}/)
      expect(profile_data['updatedAt']).to match(/^\d{4}-\d{2}-\d{2}/)
    end

    it 'returns user timestamps in ISO8601 format' do
      result = execute_graphql(query: query, context: { current_user: user })

      data = result['data']['me']
      expect(data['createdAt']).to match(/^\d{4}-\d{2}-\d{2}/)
      expect(data['updatedAt']).to match(/^\d{4}-\d{2}-\d{2}/)
    end

    context 'with workout sessions' do
      let(:query_with_sessions) do
        <<~GQL
          query Me {
            me {
              id
              workoutSessions(limit: 5) {
                id
                status
                startTime
                endTime
              }
              currentWorkoutSession {
                id
                status
              }
            }
          }
        GQL
      end

      let!(:completed_session) do
        create(:workout_session, user: user,
               start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      let!(:active_session) do
        create(:workout_session, user: user,
               start_time: 1.hour.ago, end_time: nil)
      end

      it 'returns workout sessions with limit' do
        result = execute_graphql(query: query_with_sessions, context: { current_user: user })

        sessions = result['data']['me']['workoutSessions']
        expect(sessions.length).to eq(2)
      end

      it 'returns current active workout session' do
        result = execute_graphql(query: query_with_sessions, context: { current_user: user })

        current = result['data']['me']['currentWorkoutSession']
        expect(current).to be_present
        expect(current['id']).to eq(active_session.id.to_s)
      end

      it 'returns hasActiveWorkout correctly' do
        result = execute_graphql(query: query, context: { current_user: user })

        expect(result['data']['me']['hasActiveWorkout']).to be true
      end

      it 'returns totalWorkoutSessions (only completed)' do
        result = execute_graphql(query: query, context: { current_user: user })

        # Only counts completed sessions (with end_time)
        expect(result['data']['me']['totalWorkoutSessions']).to eq(1)
      end
    end

    context 'with workout routines' do
      let(:query_with_routines) do
        <<~GQL
          query Me {
            me {
              id
              workoutRoutines(limit: 5) {
                id
                level
                workoutType
                weekNumber
                dayNumber
                generatedAt
                createdAt
                updatedAt
                totalExercises
                totalSets
                dayName
              }
            }
          }
        GQL
      end

      let!(:routine) { create(:workout_routine, user: user, workout_type: 'strength') }

      it 'returns workout routines with limit' do
        result = execute_graphql(query: query_with_routines, context: { current_user: user })

        routines = result['data']['me']['workoutRoutines']
        expect(routines.length).to eq(1)
        expect(routines.first['workoutType']).to eq('strength')
      end
    end

    context 'without profile' do
      let(:user_without_profile) { create(:user) }

      it 'returns nil for userProfile' do
        result = execute_graphql(query: query, context: { current_user: user_without_profile })

        expect(result['data']['me']['userProfile']).to be_nil
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_graphql(query: query, context: { current_user: nil })

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('sign in')
    end
  end
end
