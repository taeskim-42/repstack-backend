# frozen_string_literal: true

module Mutations
  class SyncOfflineRecords < BaseMutation
    description "Sync offline workout records to the server"

    argument :records, [Types::OfflineRecordInputType], required: true, description: "List of offline records to sync"

    field :success, Boolean, null: false
    field :synced_count, Integer, null: false
    field :failed_records, [Types::FailedSyncRecordType], null: true
    field :error, String, null: true

    def resolve(records:)
      authenticate_user!

      synced_count = 0
      failed_records = []

      ActiveRecord::Base.transaction do
        records.each do |record|
          result = sync_single_record(record)

          if result[:success]
            synced_count += 1
          else
            failed_records << {
              client_id: record[:client_id],
              error: result[:error]
            }
          end
        end
      end

      {
        success: failed_records.empty?,
        synced_count: synced_count,
        failed_records: failed_records.presence,
        error: nil
      }
    rescue GraphQL::ExecutionError
      raise
    rescue StandardError => e
      Rails.logger.error("SyncOfflineRecords error: #{e.message}")
      {
        success: false,
        synced_count: 0,
        failed_records: nil,
        error: "동기화 실패: #{e.message}"
      }
    end

    private

    def sync_single_record(record)
      # Check for duplicate (already synced)
      existing = current_user.workout_sets.find_by(client_id: record[:client_id])
      return { success: true, skipped: true } if existing

      # Find or create session for the recorded date
      session = find_or_create_offline_session(record[:recorded_at])

      # Create workout sets
      sets_count = record[:sets] || 1
      sets_count.times do |i|
        session.workout_sets.create!(
          client_id: i.zero? ? record[:client_id] : "#{record[:client_id]}-#{i + 1}",
          exercise_name: record[:exercise_name],
          weight: record[:weight],
          reps: record[:reps],
          set_number: next_set_number(session, record[:exercise_name]),
          source: "offline",
          created_at: record[:recorded_at]
        )
      end

      { success: true }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def find_or_create_offline_session(recorded_at)
      date = recorded_at.to_date

      # Find existing offline session for this date
      existing = current_user.workout_sessions.find_by(
        source: "offline",
        start_time: date.beginning_of_day..date.end_of_day
      )
      return existing if existing

      # Create new offline session
      current_user.workout_sessions.create!(
        name: "오프라인 기록 - #{date.strftime('%Y-%m-%d')}",
        source: "offline",
        start_time: recorded_at,
        end_time: recorded_at + 1.hour, # Set end_time after start_time
        status: "completed"
      )
    end

    def next_set_number(session, exercise_name)
      session.workout_sets.where(exercise_name: exercise_name).count + 1
    end
  end
end
