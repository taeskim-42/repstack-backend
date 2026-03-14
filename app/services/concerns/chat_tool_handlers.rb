# frozen_string_literal: true

# Extracted from ChatService: tool dispatch + all handle_* methods,
# condition helpers, exercise replacement, and workout completion.
#
# Submodules (all private methods, loaded via require_relative):
#   Core         — tool dispatch, structured commands, shared helpers
#   RoutineTools — generate/replace/add/delete exercise
#   WorkoutTools — record exercise, complete workout
#   AnalysisTools — check condition, submit feedback, explain plan

require_relative "chat_tool_handlers/core"
require_relative "chat_tool_handlers/routine_tools"
require_relative "chat_tool_handlers/workout_tools"
require_relative "chat_tool_handlers/analysis_tools"

module ChatToolHandlers
  extend ActiveSupport::Concern

  included do
    include ChatToolHandlers::Core
    include ChatToolHandlers::RoutineTools
    include ChatToolHandlers::WorkoutTools
    include ChatToolHandlers::AnalysisTools
  end
end
