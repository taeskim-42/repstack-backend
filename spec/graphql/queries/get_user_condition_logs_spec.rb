# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::GetUserConditionLogs, type: :graphql do
  let(:user) { create(:user) }

  let(:query) do
    <<~GQL
      query GetUserConditionLogs($days: Int) {
        getUserConditionLogs(days: $days) {
          userId
          date
          energyLevel
          stressLevel
          sleepQuality
          soreness
          motivation
          availableTime
          notes
        }
      }
    GQL
  end

  describe 'when authenticated' do
    context 'with condition logs' do
      let!(:log1) do
        create(:condition_log, user: user, date: 1.day.ago,
               energy_level: 4, stress_level: 2, sleep_quality: 4,
               motivation: 5, available_time: 60, notes: '컨디션 좋음')
      end

      let!(:log2) do
        create(:condition_log, user: user, date: 3.days.ago,
               energy_level: 2, stress_level: 4, sleep_quality: 2,
               motivation: 2, available_time: 30, notes: '피곤함')
      end

      let!(:old_log) do
        create(:condition_log, user: user, date: 10.days.ago,
               energy_level: 3, stress_level: 3, sleep_quality: 3)
      end

      it 'returns recent logs within default 7 days' do
        result = execute_graphql(query: query, context: { current_user: user })

        logs = result['data']['getUserConditionLogs']
        expect(logs.length).to eq(2)
        expect(logs.first['energyLevel']).to eq(4)
        expect(logs.first['notes']).to eq('컨디션 좋음')
      end

      it 'respects days parameter' do
        result = execute_graphql(
          query: query,
          variables: { days: 14 },
          context: { current_user: user }
        )

        logs = result['data']['getUserConditionLogs']
        expect(logs.length).to eq(3)
      end

      it 'returns logs ordered by date desc' do
        result = execute_graphql(query: query, context: { current_user: user })

        logs = result['data']['getUserConditionLogs']
        dates = logs.map { |l| Date.parse(l['date']) }
        expect(dates).to eq(dates.sort.reverse)
      end

      it 'includes all condition fields' do
        result = execute_graphql(query: query, context: { current_user: user })

        log = result['data']['getUserConditionLogs'].first
        expect(log['userId']).to eq(user.id.to_s)
        expect(log['date']).to be_present
        expect(log['energyLevel']).to be_present
        expect(log['stressLevel']).to be_present
        expect(log['sleepQuality']).to be_present
        expect(log['motivation']).to be_present
        expect(log['availableTime']).to be_present
      end
    end

    context 'without condition logs' do
      it 'returns empty array' do
        result = execute_graphql(query: query, context: { current_user: user })

        expect(result['data']['getUserConditionLogs']).to eq([])
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
