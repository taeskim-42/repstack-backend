# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::SyncOfflineRecords, type: :graphql do
  let(:user) { create(:user) }

  let(:mutation) do
    <<~GQL
      mutation SyncOfflineRecords($records: [OfflineRecordInput!]!) {
        syncOfflineRecords(input: { records: $records }) {
          success
          syncedCount
          failedRecords {
            clientId
            error
          }
          error
        }
      }
    GQL
  end

  def execute_mutation(variables = {}, current_user: user)
    RepstackBackendSchema.execute(
      mutation,
      variables: variables,
      context: { current_user: current_user }
    )
  end

  describe 'when authenticated' do
    context 'with valid records' do
      let(:records) do
        [
          {
            clientId: 'offline-1',
            exerciseName: '벤치프레스',
            weight: 60,
            reps: 10,
            recordedAt: 1.hour.ago.iso8601
          },
          {
            clientId: 'offline-2',
            exerciseName: '스쿼트',
            weight: 80,
            reps: 8,
            sets: 3,
            recordedAt: 1.hour.ago.iso8601
          }
        ]
      end

      it 'syncs all records successfully' do
        result = execute_mutation({ records: records })

        data = result['data']['syncOfflineRecords']
        expect(data['success']).to be true
        expect(data['syncedCount']).to eq(2)
        expect(data['failedRecords']).to be_nil
        expect(data['error']).to be_nil
      end

      it 'creates workout session for offline records' do
        expect do
          execute_mutation({ records: records })
        end.to change { user.workout_sessions.where(source: 'offline').count }.by(1)
      end

      it 'creates workout sets' do
        # First record: 1 set (default), Second record: 3 sets
        expect do
          execute_mutation({ records: records })
        end.to change { WorkoutSet.count }.by(4)
      end
    end

    context 'with duplicate client_id' do
      let(:records) do
        [
          {
            clientId: 'existing-1',
            exerciseName: '벤치프레스',
            weight: 60,
            reps: 10,
            recordedAt: 1.hour.ago.iso8601
          }
        ]
      end

      before do
        session = create(:workout_session, user: user, start_time: 1.hour.ago, end_time: Time.current)
        create(:workout_set, workout_session: session, client_id: 'existing-1', exercise_name: '벤치프레스')
      end

      it 'skips duplicate records' do
        result = execute_mutation({ records: records })

        data = result['data']['syncOfflineRecords']
        expect(data['success']).to be true
        expect(data['syncedCount']).to eq(1) # Still counted as synced (skipped)
      end
    end

    context 'with records on different dates' do
      let(:records) do
        [
          {
            clientId: 'day1-1',
            exerciseName: '벤치프레스',
            weight: 60,
            reps: 10,
            recordedAt: 2.days.ago.iso8601
          },
          {
            clientId: 'day2-1',
            exerciseName: '스쿼트',
            weight: 80,
            reps: 8,
            recordedAt: 1.day.ago.iso8601
          }
        ]
      end

      it 'creates separate sessions for different dates' do
        expect do
          execute_mutation({ records: records })
        end.to change { user.workout_sessions.where(source: 'offline').count }.by(2)
      end
    end

    context 'with empty records' do
      it 'returns success with zero synced' do
        result = execute_mutation({ records: [] })

        data = result['data']['syncOfflineRecords']
        expect(data['success']).to be true
        expect(data['syncedCount']).to eq(0)
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns error' do
      result = execute_mutation({ records: [] }, current_user: nil)

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('Authentication required')
    end
  end
end
