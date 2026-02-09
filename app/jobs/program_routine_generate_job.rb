# frozen_string_literal: true

# Asynchronously generates all weekly routines for a TrainingProgram
# Queued after ProgramGenerator successfully creates a program
class ProgramRoutineGenerateJob < ApplicationJob
  queue_as :routine_generation

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(training_program_id)
    program = TrainingProgram.find(training_program_id)
    user = program.user

    Rails.logger.info("[ProgramRoutineGenerateJob] Starting for program #{program.id} (#{program.total_weeks} weeks)")

    generator = ProgramRoutineGenerator.new(user: user, program: program)
    generator.generate_all

    Rails.logger.info("[ProgramRoutineGenerateJob] Completed for program #{program.id}")
  end
end
