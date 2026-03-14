# frozen_string_literal: true

# Exclude directories that are loaded explicitly via require_relative in their
# parent modules. Zeitwerk must not autoload these since their namespace
# declarations (e.g. module AiTrainer::RoutineGenerator::ExerciseBuilder) would
# conflict with parent class/module definitions loaded later.
Rails.autoloaders.each do |autoloader|
  autoloader.ignore(
    Rails.root.join("lib/ai_trainer/data"),
    Rails.root.join("lib/ai_trainer/workout_programs"),
    Rails.root.join("lib/ai_trainer/routine_generator"),
    Rails.root.join("lib/ai_trainer/creative_routine"),
    Rails.root.join("lib/ai_trainer/program_generator"),
    Rails.root.join("lib/ai_trainer/level_test"),
    Rails.root.join("lib/ai_trainer/dynamic_routine"),
    Rails.root.join("lib/ai_trainer/llm_gateway"),
    Rails.root.join("lib/ai_trainer/condition"),
    Rails.root.join("lib/ai_trainer/feedback"),
    Rails.root.join("lib/ai_trainer/level_assessment"),
    Rails.root.join("lib/ai_trainer/shared"),
    Rails.root.join("lib/ai_trainer/tool_based"),
    Rails.root.join("app/services/concerns/chat_routine_formatter"),
    Rails.root.join("app/services/concerns/chat_prompt_builder"),
    Rails.root.join("app/services/concerns/chat_onboarding"),
    Rails.root.join("app/services/concerns/chat_tool_handlers")
  )
end
