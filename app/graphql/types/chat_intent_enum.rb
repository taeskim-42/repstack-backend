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
    value "LEVEL_ASSESSMENT", "New user level assessment (onboarding)"
    value "PROMOTION_ELIGIBLE", "User is eligible for level promotion test"
    value "REPLACE_EXERCISE", "Exercise replaced in routine"
    value "ADD_EXERCISE", "Exercise added to routine"
    value "REGENERATE_ROUTINE", "Routine regenerated with new exercises"
  end
end
