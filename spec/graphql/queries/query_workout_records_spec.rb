# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::QueryWorkoutRecords, type: :graphql do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let(:query) do
    <<~GQL
      query QueryWorkoutRecords($input: QueryRecordsInput!) {
        queryWorkoutRecords(input: $input) {
          success
          interpretation
          records {
            exerciseName
            weight
            reps
            date
          }
          summary {
            totalSets
            maxWeight
            avgWeight
            maxReps
          }
          error
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
    let!(:session) do
      create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
    end

    let!(:bench_set1) do
      create(:workout_set, workout_session: session, exercise_name: '벤치프레스', weight: 60, reps: 8, set_number: 1)
    end

    let!(:bench_set2) do
      create(:workout_set, workout_session: session, exercise_name: '벤치프레스', weight: 70, reps: 6, set_number: 2)
    end

    let!(:squat_set) do
      create(:workout_set, workout_session: session, exercise_name: '스쿼트', weight: 100, reps: 5, set_number: 1)
    end

    context 'with exercise name query' do
      it 'returns filtered records' do
        result = execute_query({ input: { query: '벤치프레스 기록' } })

        data = result['data']['queryWorkoutRecords']
        expect(data['success']).to be true
        # Records are grouped by date+exercise, so 2 sets on same day = 1 record
        expect(data['records'].count).to eq(1)
        expect(data['records'].map { |r| r['exerciseName'] }).to all(include('벤치프레스'))
        expect(data['summary']['maxWeight']).to eq(70)
        expect(data['summary']['totalSets']).to eq(2) # But totalSets counts all sets
      end
    end

    context 'with date range' do
      it 'returns records within date range' do
        result = execute_query({
                                 input: {
                                   query: '기록 조회',
                                   dateRange: {
                                     startDate: 2.days.ago.strftime('%Y-%m-%d'),
                                     endDate: Date.current.strftime('%Y-%m-%d')
                                   }
                                 }
                               })

        data = result['data']['queryWorkoutRecords']
        expect(data['success']).to be true
        # Records are grouped by date+exercise: 벤치프레스(1) + 스쿼트(1) = 2
        expect(data['records'].count).to eq(2)
      end

      it 'excludes records outside date range' do
        result = execute_query({
                                 input: {
                                   query: '기록 조회',
                                   dateRange: {
                                     startDate: 10.days.ago.strftime('%Y-%m-%d'),
                                     endDate: 5.days.ago.strftime('%Y-%m-%d')
                                   }
                                 }
                               })

        data = result['data']['queryWorkoutRecords']
        expect(data['success']).to be true
        expect(data['records'].count).to eq(0)
      end
    end

    context 'with natural language parsing' do
      it 'parses "이번주" correctly' do
        result = execute_query({ input: { query: '이번주 벤치프레스' } })

        data = result['data']['queryWorkoutRecords']
        expect(data['success']).to be true
        expect(data['interpretation']).to include('벤치프레스')
      end

      it 'parses "지난주" correctly' do
        result = execute_query({ input: { query: '지난주 스쿼트' } })

        data = result['data']['queryWorkoutRecords']
        expect(data['success']).to be true
      end
    end

    context 'with empty results' do
      it 'returns empty records with success' do
        result = execute_query({ input: { query: '풀업 기록' } })

        data = result['data']['queryWorkoutRecords']
        expect(data['success']).to be true
        expect(data['records']).to be_empty
        expect(data['summary']).to be_nil # Summary is nil when no records
      end
    end

    context 'does not return other user records' do
      let!(:other_session) do
        create(:workout_session, user: other_user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      let!(:other_set) do
        create(:workout_set, workout_session: other_session, exercise_name: '벤치프레스', weight: 200, reps: 1)
      end

      it 'only returns current user records' do
        result = execute_query({ input: { query: '벤치프레스' } })

        data = result['data']['queryWorkoutRecords']
        weights = data['records'].map { |r| r['weight'] }
        expect(weights).not_to include(200)
        expect(data['summary']['maxWeight']).to eq(70)
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns error' do
      result = execute_query({ input: { query: '벤치프레스' } }, current_user: nil)

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('sign in')
    end
  end
end
