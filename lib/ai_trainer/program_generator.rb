# frozen_string_literal: true

require_relative "constants"
require_relative "program_generator/prompt_builder"
require_relative "program_generator/defaults"
require_relative "shared/json_extractor"

module AiTrainer
  # Generates long-term training programs using RAG + LLM
  # Called after onboarding consultation to create personalized multi-week programs
  #
  # Key features:
  # - Uses RAG to search fitness knowledge for program design
  # - LLM generates periodized program based on user profile
  # - Stores framework (weekly_plan, split_schedule) not daily routines
  # - Daily routines are generated dynamically based on program context
  class ProgramGenerator
    include Constants
    include ProgramGenerator::PromptBuilder
    include ProgramGenerator::Defaults
    include Shared::JsonExtractor

    # Default program configurations by experience level
    DEFAULT_CONFIGS = {
      beginner: {
        weeks: 8,
        days_per_week: 3,
        periodization: "linear",
        split: "full_body"
      },
      intermediate: {
        weeks: 12,
        days_per_week: 4,
        periodization: "linear",
        split: "upper_lower"
      },
      advanced: {
        weeks: 12,
        days_per_week: 5,
        periodization: "block",
        split: "ppl"
      }
    }.freeze

    class << self
      def generate(user:)
        new(user: user).generate
      end
    end

    def initialize(user:)
      @user = user
      @profile = user.user_profile
      @collected_data = @profile&.fitness_factors&.dig("collected_data") || {}
    end

    def generate
      Rails.logger.info("[ProgramGenerator] Starting program generation for user #{@user.id}")

      context = build_user_context
      rag_knowledge = search_program_knowledge(context)
      prompt = build_prompt(context, rag_knowledge)
      response = call_llm(prompt)

      if response[:success]
        result = parse_and_create_program(response[:content], context, rag_knowledge)
        Rails.logger.info("[ProgramGenerator] Program created: #{result[:program]&.id}")

        if result[:success] && result[:program]
          schedule_routine_generation(result[:program])
        end

        result
      else
        Rails.logger.error("[ProgramGenerator] LLM call failed: #{response[:error]}")
        { success: false, error: response[:error] }
      end
    rescue StandardError => e
      Rails.logger.error("[ProgramGenerator] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      { success: false, error: e.message }
    end

    private

    def schedule_routine_generation(program)
      generator = ProgramRoutineGenerator.new(user: program.user, program: program)

      begin
        generator.generate_week(program.current_week)
        Rails.logger.info("[ProgramGenerator] Week #{program.current_week} generated synchronously for program #{program.id}")
      rescue StandardError => e
        Rails.logger.error("[ProgramGenerator] Sync week #{program.current_week} failed: #{e.class} #{e.message}")
      end

      remaining_weeks = (1..program.total_weeks).to_a - [ program.current_week ]
      return if remaining_weeks.empty?

      if sidekiq_workers_available?
        ProgramRoutineGenerateJob.perform_later(program.id)
        Rails.logger.info("[ProgramGenerator] Queued remaining routine generation for program #{program.id}")
      else
        Rails.logger.info("[ProgramGenerator] No Sidekiq — generating remaining weeks in background thread for program #{program.id}")
        Thread.new do
          Rails.application.executor.wrap do
            generator2 = ProgramRoutineGenerator.new(user: program.user, program: program)
            generator2.generate_all
            Rails.logger.info("[ProgramGenerator] Background routine generation completed for program #{program.id}")
          end
        rescue StandardError => e
          Rails.logger.error("[ProgramGenerator] Background thread crashed for program #{program.id}: #{e.class} #{e.message}")
        end
      end
    end

    def sidekiq_workers_available?
      processes = Sidekiq::ProcessSet.new
      processes.any?
    rescue StandardError
      false
    end

    def build_user_context
      experience = @collected_data["experience"] || @profile&.current_level || "beginner"
      tier = normalize_tier(experience)

      frequency = @collected_data["frequency"] || "주 3회"
      days_per_week = parse_days_per_week(frequency, DEFAULT_CONFIGS[tier][:days_per_week])
      config = DEFAULT_CONFIGS[tier]
      preferred_weeks = parse_program_weeks(@collected_data["program_duration"], config[:weeks])

      Rails.logger.info("[ProgramGenerator] collected_data: #{@collected_data.inspect}")
      Rails.logger.info("[ProgramGenerator] frequency=#{frequency}, days_per_week=#{days_per_week}, preferred_weeks=#{preferred_weeks}")

      {
        user_id: @user.id,
        name: @user.name,
        tier: tier,
        tier_korean: tier_korean(tier),
        numeric_level: @profile&.numeric_level || 1,
        goal: @collected_data["goals"] || @profile&.fitness_goal || "근력 향상",
        focus_areas: @collected_data["focus_areas"],
        injuries: @collected_data["injuries"],
        preferences: @collected_data["preferences"],
        environment: @collected_data["environment"] || "헬스장",
        frequency: frequency,
        days_per_week: days_per_week,
        schedule: @collected_data["schedule"],
        default_weeks: preferred_weeks,
        default_periodization: config[:periodization],
        default_split: config[:split],
        height: @profile&.height,
        weight: @profile&.weight
      }
    end

    def search_program_knowledge(context)
      query_parts = []
      query_parts << "#{context[:tier_korean]} 운동 프로그램"
      query_parts << context[:goal] if context[:goal].present?
      query_parts << "#{context[:days_per_week]}일 분할" if context[:days_per_week]
      query = query_parts.join(" ")

      results = RagSearchService.search(
        query,
        limit: 5,
        knowledge_types: [ "routine_design", "program_periodization" ],
        filters: { difficulty_level: context[:tier].to_s }
      )

      {
        query: query,
        chunks: results.map { |r| r[:content] }.compact.first(3),
        sources: results.map { |r| r[:source] }.compact.uniq
      }
    rescue StandardError => e
      Rails.logger.warn("[ProgramGenerator] RAG search failed: #{e.message}")
      { query: "", chunks: [], sources: [] }
    end

    def call_llm(prompt)
      LlmGateway.chat(
        prompt: prompt[:user],
        task: :routine_generation,
        system: prompt[:system]
      )
    end

    def parse_and_create_program(content, context, rag_knowledge)
      json_str = extract_json(content)
      data = JSON.parse(json_str)

      split_schedule = data["split_schedule"] || default_split_schedule(context)
      split_schedule = enforce_days_per_week(split_schedule, context[:days_per_week])

      program = @user.training_programs.create!(
        name: data["program_name"] || "#{context[:tier_korean]} 운동 프로그램",
        status: "active",
        total_weeks: data["total_weeks"] || context[:default_weeks] || DEFAULT_CONFIGS[context[:tier]][:weeks],
        current_week: 1,
        goal: context[:goal],
        periodization_type: data["periodization_type"] || context[:default_periodization],
        weekly_plan: data["weekly_plan"] || default_weekly_plan(context),
        split_schedule: split_schedule,
        generation_context: {
          user_context: context.except(:user_id),
          rag_query: rag_knowledge[:query],
          rag_sources: rag_knowledge[:sources],
          generated_at: Time.current.iso8601
        },
        started_at: Time.current
      )

      {
        success: true,
        program: program,
        coach_message: data["coach_message"] || default_coach_message(context)
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[ProgramGenerator] JSON parse error: #{e.message}")
      create_default_program(context)
    end

    def enforce_days_per_week(schedule, days_per_week)
      return schedule if days_per_week.nil?

      rest_focus_keywords = %w[휴식 rest off]
      training_days = schedule.select { |_, v| rest_focus_keywords.none? { |kw| v["focus"]&.downcase&.include?(kw) } }

      if training_days.size == days_per_week
        Rails.logger.info("[ProgramGenerator] split_schedule OK: #{training_days.size} training days match days_per_week=#{days_per_week}")
        return schedule
      end

      Rails.logger.warn("[ProgramGenerator] split_schedule mismatch: #{training_days.size} training days vs days_per_week=#{days_per_week}, using default")
      default_split_schedule({ days_per_week: days_per_week })
    end

    def parse_program_weeks(duration, default)
      return default if duration.blank?

      match = duration.match(/(\d+)\s*(?:주|weeks?)/)
      weeks = match ? match[1].to_i : default
      weeks.clamp(2, 24)
    end

    def parse_days_per_week(frequency, default)
      return default if frequency.blank?

      match = frequency.match(/(\d+)\s*(?:회|일|번|days?)/)
      days = match ? match[1].to_i : default
      days.clamp(1, 7)
    end

    def normalize_tier(experience)
      case experience.to_s.downcase
      when "beginner", "초보", "초급"
        :beginner
      when "advanced", "고급", "상급"
        :advanced
      else
        :intermediate
      end
    end

    def tier_korean(tier)
      { beginner: "초급", intermediate: "중급", advanced: "고급" }[tier]
    end
  end
end
