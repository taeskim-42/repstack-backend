# frozen_string_literal: true

module Types
  class ChatIntentEnum < Types::BaseEnum
    description "User intent classification for chat messages"

    value "RECORD_EXERCISE", "Recording workout (e.g., '벤치프레스 60kg 8회')"
    value "QUERY_RECORDS", "Querying workout history (e.g., '지난주 벤치 기록')"
    value "CHECK_CONDITION", "Checking condition (e.g., '오늘 피곤해')"
    value "GENERATE_ROUTINE", "Generating routine (e.g., '오늘 루틴 만들어줘')"
    value "SUBMIT_FEEDBACK", "Submitting feedback (e.g., '런지가 힘들었어')"
    value "GENERAL_CHAT", "General conversation handled by AI"
    value "WELCOME", "Welcome message for newly onboarded users"
    value "WELCOME_WITH_ROUTINE", "Welcome message with long-term plan and first routine"
    value "LEVEL_ASSESSMENT", "New user level assessment (onboarding)"
    value "CONSULTATION", "AI consultation for new users (form completed, AI chat in progress)"
    value "TRAINING_PROGRAM", "Training program created after AI consultation complete"
    value "DAILY_GREETING", "Daily greeting for returning users"
    value "PROMOTION_ELIGIBLE", "User is eligible for level promotion test"
    value "REPLACE_EXERCISE", "Exercise replaced in routine"
    value "ADD_EXERCISE", "Exercise added to routine"
    value "DELETE_EXERCISE", "Exercise deleted from routine"
    value "REGENERATE_ROUTINE", "Routine regenerated with new exercises"
    value "DELETE_ROUTINE", "Routine deleted"
    value "EXPLAIN_LONG_TERM_PLAN", "Long-term workout plan explanation"
    value "CONDITION_AND_ROUTINE", "Condition checked and routine generated together"
    value "WORKOUT_COMPLETED", "Workout session completed"
    value "FEEDBACK_RECEIVED", "Feedback received and processed"
    value "REST_DAY", "Today is a rest day in the training program"
  end
end
