# frozen_string_literal: true

module Mutations
  class RecordWorkout < BaseMutation
    description "Record a completed workout"

    argument :input, Types::WorkoutRecordInputType, required: true,
      description: "Workout record input data"

    field :success, Boolean, null: false
    field :workout_record, Types::WorkoutRecordSummaryType, null: true
    field :error, String, null: true

    def resolve(input:)
      authenticate_user!

      input_hash = input.to_h.deep_transform_keys { |k| k.to_s.underscore.to_sym }

      ActiveRecord::Base.transaction do
        # Create or find workout session
        session = find_or_create_session(input_hash)

        # Record exercises and sets
        record_exercises(session, input_hash[:exercises])

        # Update session completion
        session.update!(
          status: input_hash[:completion_status]&.downcase || "completed",
          end_time: Time.current,
          notes: input_hash[:notes],
          total_duration: input_hash[:total_duration]
        )

        # Create workout record for analytics
        record = WorkoutRecord.create!(
          user: current_user,
          workout_session: session,
          routine_id: input_hash[:routine_id],
          date: input_hash[:date] ? Time.parse(input_hash[:date]) : Time.current,
          total_duration: input_hash[:total_duration],
          calories_burned: input_hash[:calories_burned],
          average_heart_rate: input_hash[:average_heart_rate],
          perceived_exertion: input_hash[:perceived_exertion],
          completion_status: input_hash[:completion_status]
        )

        {
          success: true,
          workout_record: {
            id: record.id,
            date: record.date.iso8601,
            total_duration: record.total_duration,
            completion_status: record.completion_status
          },
          error: nil
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, workout_record: nil, error: e.message }
    rescue StandardError => e
      Rails.logger.error("RecordWorkout error: #{e.message}")
      { success: false, workout_record: nil, error: "Failed to record workout" }
    end

    private

    def find_or_create_session(input)
      # Try to find an active session
      session = current_user.workout_sessions.find_by(status: "active")
      return session if session

      # Create new session
      current_user.workout_sessions.create!(
        start_time: input[:date] ? Time.parse(input[:date]) : Time.current,
        status: "active"
      )
    end

    def record_exercises(session, exercises)
      return unless exercises

      exercises.each do |exercise|
        exercise[:completed_sets]&.each do |set|
          session.workout_sets.create!(
            exercise_name: exercise[:exercise_name],
            target_muscle: exercise[:target_muscle],
            set_number: set[:set_number],
            reps: set[:reps],
            weight: set[:weight],
            duration_seconds: set[:duration],
            rpe: set[:rpe],
            notes: set[:notes]
          )
        end
      end
    end
  end
end
