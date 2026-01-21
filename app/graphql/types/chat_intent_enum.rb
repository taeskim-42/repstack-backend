# frozen_string_literal: true

module Types
  class ChatIntentEnum < Types::BaseEnum
    description "User intent classification for chat messages"

    value "RECORD_EXERCISE", "Recording workout (e.g., '벤치프레스 60kg 8회')"
    value "QUERY_RECORDS", "Querying workout history (e.g., '지난주 벤치 기록')"
    value "CHECK_CONDITION", "Checking condition (e.g., '오늘 피곤해')"
    value "GENERATE_ROUTINE", "Generating routine (e.g., '오늘 루틴 만들어줘')"
    value "SUBMIT_FEEDBACK", "Submitting feedback (e.g., '런지가 힘들었어')"
    value "GENERAL_CHAT", "General fitness-related conversation"
    value "OFF_TOPIC", "Non-fitness related message"
  end
end
