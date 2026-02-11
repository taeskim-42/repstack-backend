# frozen_string_literal: true

module Simulation
  module Personas
    # Agent Service E2E test persona (10 users × 28 days)
    # - Same structure as MarathonUser but with reduced sets (3-4 vs 8-16)
    # - Reduces Agent API calls by ~75%, keeping total cost under $8
    class AgentTestUser
      DAILY_WORKOUT_PROBABILITY = 0.85

      def actions_for_day(day_number)
        if day_number == 1
          return [[Actions::OnboardingAction, {}]]
        end

        actions = []

        # Advance week every 7 days (starting day 8)
        if day_number > 1 && (day_number - 1) % 7 == 0
          actions << [Actions::WeekAdvanceAction, {}]
        end

        if rand < DAILY_WORKOUT_PROBABILITY
          actions << [Actions::ConditionCheckAction, {}]
          actions << [Actions::RoutineGenerationAction, {}]
          actions << [Actions::ExerciseRecordingAction, { sets_count: rand(3..4) }]
          actions << [Actions::WorkoutCompletionAction, {}]

          # Alternate between simple and detailed feedback
          detailed = day_number % 3 == 0
          actions << [Actions::FeedbackAction, { detailed: detailed }]
        end

        actions
      end

      def persona_type
        :agent_test
      end
    end
  end
end
