# frozen_string_literal: true

module Types
  class FeedbackTypeEnum < Types::BaseEnum
    description "Type of workout feedback"

    value "DIFFICULTY", "Feedback about workout difficulty"
    value "EFFECTIVENESS", "Feedback about workout effectiveness"
    value "ENJOYMENT", "Feedback about workout enjoyment"
    value "TIME", "Feedback about workout duration/timing"
    value "OTHER", "Other feedback"
  end
end
