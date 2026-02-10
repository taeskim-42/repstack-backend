# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

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

    # Default program configurations by experience level
    DEFAULT_CONFIGS = {
      beginner: {
        weeks: 8,
        days_per_week: 3,
        periodization: "linear",
        split: "full_body"  # 전신 운동
      },
      intermediate: {
        weeks: 12,
        days_per_week: 4,
        periodization: "linear",
        split: "upper_lower"  # 상하체 분할
      },
      advanced: {
        weeks: 12,
        days_per_week: 5,
        periodization: "block",
        split: "ppl"  # Push/Pull/Legs
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

      # 1. Build user context from consultation data
      context = build_user_context

      # 2. Search RAG for program design knowledge
      rag_knowledge = search_program_knowledge(context)

      # 3. Build and call LLM to generate program
      prompt = build_prompt(context, rag_knowledge)
      response = call_llm(prompt)

      if response[:success]
        # 4. Parse response and create TrainingProgram
        result = parse_and_create_program(response[:content], context, rag_knowledge)
        Rails.logger.info("[ProgramGenerator] Program created: #{result[:program]&.id}")

        # 5. Queue bulk routine generation for the entire program
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

      # Generate week 1 synchronously so the first routine request is instant
      begin
        generator.generate_week(program.current_week)
        Rails.logger.info("[ProgramGenerator] Week #{program.current_week} generated synchronously for program #{program.id}")
      rescue StandardError => e
        Rails.logger.error("[ProgramGenerator] Sync week #{program.current_week} failed: #{e.class} #{e.message}")
      end

      # Background the remaining weeks
      remaining_weeks = (1..program.total_weeks).to_a - [program.current_week]
      return if remaining_weeks.empty?

      if sidekiq_workers_available?
        ProgramRoutineGenerateJob.perform_later(program.id)
        Rails.logger.info("[ProgramGenerator] Queued remaining routine generation for program #{program.id}")
      else
        Rails.logger.info("[ProgramGenerator] No Sidekiq — generating remaining weeks in background thread for program #{program.id}")
        Thread.new do
          Rails.application.executor.wrap do
            generator2 = ProgramRoutineGenerator.new(user: program.user, program: program)
            generator2.generate_all # generate_all skips already-generated weeks
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
      # Extract experience level (tier)
      experience = @collected_data["experience"] || @profile&.current_level || "beginner"
      tier = normalize_tier(experience)

      frequency = @collected_data["frequency"] || "주 3회"
      days_per_week = parse_days_per_week(frequency, DEFAULT_CONFIGS[tier][:days_per_week])

      # Get default config for this tier
      config = DEFAULT_CONFIGS[tier]

      # Use user's preferred duration from consultation, fallback to tier default
      preferred_weeks = parse_program_weeks(@collected_data["program_duration"], config[:weeks])

      Rails.logger.info("[ProgramGenerator] collected_data: #{@collected_data.inspect}")
      Rails.logger.info("[ProgramGenerator] frequency=#{frequency}, days_per_week=#{days_per_week}, preferred_weeks=#{preferred_weeks}")

      {
        # User info
        user_id: @user.id,
        name: @user.name,

        # Experience & Level
        tier: tier,
        tier_korean: tier_korean(tier),
        numeric_level: @profile&.numeric_level || 1,

        # Goals
        goal: @collected_data["goals"] || @profile&.fitness_goal || "근력 향상",
        focus_areas: @collected_data["focus_areas"],

        # Constraints
        injuries: @collected_data["injuries"],
        preferences: @collected_data["preferences"],
        environment: @collected_data["environment"] || "헬스장",

        # Schedule
        frequency: frequency,
        days_per_week: days_per_week,
        schedule: @collected_data["schedule"],

        # Program defaults (user preference > tier default)
        default_weeks: preferred_weeks,
        default_periodization: config[:periodization],
        default_split: config[:split],

        # Physical info
        height: @profile&.height,
        weight: @profile&.weight
      }
    end

    def search_program_knowledge(context)
      # Build search query based on user context
      query_parts = []
      query_parts << "#{context[:tier_korean]} 운동 프로그램"
      query_parts << context[:goal] if context[:goal].present?
      query_parts << "#{context[:days_per_week]}일 분할" if context[:days_per_week]

      query = query_parts.join(" ")

      # Search RAG for routine_design knowledge
      results = RagSearchService.search(
        query,
        limit: 5,
        knowledge_types: ["routine_design", "program_periodization"],
        filters: { difficulty_level: context[:tier].to_s }
      )

      # Format for prompt
      {
        query: query,
        chunks: results.map { |r| r[:content] }.compact.first(3),
        sources: results.map { |r| r[:source] }.compact.uniq
      }
    rescue StandardError => e
      Rails.logger.warn("[ProgramGenerator] RAG search failed: #{e.message}")
      { query: "", chunks: [], sources: [] }
    end

    def build_prompt(context, rag_knowledge)
      system_prompt = <<~SYSTEM
        당신은 전문 피트니스 트레이너입니다.
        사용자의 상담 결과를 바탕으로 장기 운동 프로그램 프레임워크를 설계합니다.

        ## 프레임워크 개념
        - 매일 루틴을 미리 정하지 않음
        - **주차별 테마/볼륨**과 **요일별 분할**만 정의
        - 매일 운동 시: 프레임워크 + 컨디션 + 피드백 → 동적 루틴 생성

        ## 주기화 원칙
        1. **선형 주기화 (Linear)**: 초보자용, 매주 점진적 증가
        2. **비선형/물결형 (Undulating)**: 중급자용, 주 내 강도 변화
        3. **블록 주기화 (Block)**: 고급자용, 4주 단위 목표 블록

        ## 디로드 가이드라인
        - 초급: 4주마다 (또는 불필요)
        - 중급: 4-6주마다 1주 디로드
        - 고급: 3-4주마다 1주 디로드, 또는 매 블록 후

        ## 분할 운동 가이드라인
        - 주 2-3회: 전신 운동 (Full Body)
        - 주 4회: 상하체 분할 (Upper/Lower)
        - 주 5-6회: PPL (Push/Pull/Legs) 또는 부위별 분할
      SYSTEM

      user_prompt = <<~USER
        ## 사용자 정보
        - 이름: #{context[:name]}
        - 경험 수준: #{context[:tier_korean]} (레벨 #{context[:numeric_level]}/8)
        - 운동 목표: #{context[:goal]}
        - 운동 가능 빈도: #{context[:frequency]}
        #{context[:focus_areas].present? ? "- 집중 부위: #{context[:focus_areas]}" : ""}
        #{context[:injuries].present? && context[:injuries] != "없음" ? "- 부상/주의: #{context[:injuries]}" : ""}
        #{context[:preferences].present? ? "- 선호/비선호: #{context[:preferences]}" : ""}
        - 운동 환경: #{context[:environment]}
        #{context[:schedule].present? ? "- 선호 시간대: #{context[:schedule]}" : ""}

        #{rag_knowledge[:chunks].any? ? "## 참고 지식\n#{rag_knowledge[:chunks].join("\n\n")}" : ""}

        ## 요청
        #{weeks_instruction(context)}

        ## 응답 형식 (JSON)
        ```json
        {
          "program_name": "프로그램 이름 (예: N주 다이어트 프로그램)",
          "total_weeks": "사용자 경험/목표에 맞는 주차 (4-24주)",
          "periodization_type": "linear|undulating|block",
          "weekly_plan": {
            "1-N": {
              "phase": "적응기",
              "theme": "기본 동작 학습, 폼 교정",
              "volume_modifier": 0.8,
              "focus": "운동 패턴 익히기, 낮은 무게"
            },
            "...": "total_weeks에 맞게 주차별 계획 구성",
            "마지막주": {
              "phase": "디로드",
              "theme": "회복",
              "volume_modifier": 0.6,
              "focus": "능동적 회복, 유연성"
            }
          },
          "split_schedule": {
            "1": {"focus": "상체", "muscles": ["chest", "back", "shoulders"]},
            "2": {"focus": "하체", "muscles": ["legs", "core"]},
            "3": {"focus": "휴식", "muscles": []},
            "4": {"focus": "상체", "muscles": ["chest", "back", "shoulders"]},
            "5": {"focus": "하체", "muscles": ["legs", "core"]},
            "6": {"focus": "휴식", "muscles": []},
            "7": {"focus": "휴식", "muscles": []}
          },
          "coach_message": "프로그램 소개 및 동기부여 메시지 (2-3문장)"
        }
        ```

        주의사항:
        - #{weeks_note(context)}
        - weekly_plan의 키는 "1-3", "4-8" 등 주차 범위 문자열
        - split_schedule의 키는 요일 번호 (1=월, 7=일)
        - ⚠️ 매우 중요: 사용자의 운동 가능 빈도는 **주 #{context[:days_per_week]}회**입니다
        - split_schedule에서 운동일(휴식이 아닌 날)은 반드시 **#{context[:days_per_week]}일**이어야 합니다
        - 나머지 요일은 반드시 {"focus": "휴식", "muscles": []}로 설정하세요
        - 부상이 있다면 해당 부위를 피하는 분할 구성
        - coach_message는 한글로 친근하게
      USER

      { system: system_prompt, user: user_prompt }
    end

    def call_llm(prompt)
      # Use routine_generation task for better quality
      LlmGateway.chat(
        prompt: prompt[:user],
        task: :routine_generation,
        system: prompt[:system]
      )
    end

    def parse_and_create_program(content, context, rag_knowledge)
      # Extract JSON from response
      json_str = extract_json(content)
      data = JSON.parse(json_str)

      # Validate split_schedule: ensure training days match days_per_week
      split_schedule = data["split_schedule"] || default_split_schedule(context)
      split_schedule = enforce_days_per_week(split_schedule, context[:days_per_week])

      # Create TrainingProgram
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
      # Fallback to default program
      create_default_program(context)
    end

    def extract_json(text)
      if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif text.include?("{")
        start_idx = text.index("{")
        end_idx = text.rindex("}")
        text[start_idx..end_idx] if start_idx && end_idx
      else
        text
      end
    end

    def create_default_program(context)
      program = @user.training_programs.create!(
        name: "#{context[:tier_korean]} #{context[:goal]} 프로그램",
        status: "active",
        total_weeks: context[:default_weeks] || DEFAULT_CONFIGS[context[:tier]][:weeks],
        current_week: 1,
        goal: context[:goal],
        periodization_type: context[:default_periodization],
        weekly_plan: default_weekly_plan(context),
        split_schedule: default_split_schedule(context),
        generation_context: {
          user_context: context.except(:user_id),
          fallback: true,
          generated_at: Time.current.iso8601
        },
        started_at: Time.current
      )

      {
        success: true,
        program: program,
        coach_message: default_coach_message(context)
      }
    end

    def default_weekly_plan(context)
      weeks = context[:default_weeks] || 8
      tier = context[:tier]

      case tier
      when :beginner
        {
          "1-2" => { "phase" => "적응기", "theme" => "기본 동작 학습", "volume_modifier" => 0.7 },
          "3-6" => { "phase" => "성장기", "theme" => "점진적 과부하", "volume_modifier" => 0.9 },
          "7-8" => { "phase" => "강화기", "theme" => "볼륨 증가", "volume_modifier" => 1.0 }
        }
      when :intermediate
        {
          "1-3" => { "phase" => "적응기", "theme" => "기본 동작 점검", "volume_modifier" => 0.8 },
          "4-8" => { "phase" => "성장기", "theme" => "점진적 과부하", "volume_modifier" => 1.0 },
          "9-11" => { "phase" => "강화기", "theme" => "고강도 훈련", "volume_modifier" => 1.1 },
          "12" => { "phase" => "디로드", "theme" => "회복", "volume_modifier" => 0.6 }
        }
      else # advanced
        {
          "1-4" => { "phase" => "근력 블록", "theme" => "고중량 저반복", "volume_modifier" => 0.9 },
          "5-8" => { "phase" => "근비대 블록", "theme" => "중량 고반복", "volume_modifier" => 1.1 },
          "9-11" => { "phase" => "피킹 블록", "theme" => "최대 근력 도전", "volume_modifier" => 1.0 },
          "12" => { "phase" => "디로드", "theme" => "회복", "volume_modifier" => 0.5 }
        }
      end
    end

    def default_split_schedule(context)
      days = context[:days_per_week] || 3

      case days
      when 1..2
        # Full body, 2-3 days
        {
          "1" => { "focus" => "전신", "muscles" => %w[legs chest back shoulders core] },
          "3" => { "focus" => "전신", "muscles" => %w[legs chest back shoulders core] },
          "5" => { "focus" => "전신", "muscles" => %w[legs chest back shoulders core] }
        }
      when 3
        # Full body, 3 days
        {
          "1" => { "focus" => "전신 A", "muscles" => %w[legs chest back] },
          "3" => { "focus" => "전신 B", "muscles" => %w[shoulders arms core] },
          "5" => { "focus" => "전신 C", "muscles" => %w[legs back shoulders] }
        }
      when 4
        # Upper/Lower split
        {
          "1" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
          "2" => { "focus" => "하체", "muscles" => %w[legs core] },
          "4" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
          "5" => { "focus" => "하체", "muscles" => %w[legs core] }
        }
      when 5..6
        # PPL split
        {
          "1" => { "focus" => "밀기 (Push)", "muscles" => %w[chest shoulders arms] },
          "2" => { "focus" => "당기기 (Pull)", "muscles" => %w[back arms] },
          "3" => { "focus" => "하체 (Legs)", "muscles" => %w[legs core] },
          "4" => { "focus" => "밀기 (Push)", "muscles" => %w[chest shoulders arms] },
          "5" => { "focus" => "당기기 (Pull)", "muscles" => %w[back arms] },
          "6" => { "focus" => "하체 (Legs)", "muscles" => %w[legs core] }
        }
      else
        # Default 4-day split
        {
          "1" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
          "2" => { "focus" => "하체", "muscles" => %w[legs core] },
          "4" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
          "5" => { "focus" => "하체", "muscles" => %w[legs core] }
        }
      end
    end

    def default_coach_message(context)
      goal = context[:goal] || "건강한 몸"
      weeks = context[:default_weeks] || 8
      tier = context[:tier_korean] || "중급자"

      "#{context[:name]}님을 위한 #{weeks}주 #{goal} 프로그램을 준비했어요! " \
      "#{tier} 레벨에 맞게 점진적으로 난이도를 높여갈게요. " \
      "매일 컨디션과 피드백을 반영해서 최적의 루틴을 만들어드릴게요! 💪"
    end

    def weeks_instruction(context)
      "위 정보를 바탕으로 **#{context[:default_weeks]}주** 장기 운동 프로그램 프레임워크를 JSON으로 생성해주세요.\n" \
      "⚠️ 사용자가 상담에서 희망한 기간(#{context[:default_weeks]}주)을 반드시 반영하세요!"
    end

    def weeks_note(context)
      "total_weeks는 반드시 #{context[:default_weeks]}주로 설정 (사용자가 상담에서 선택한 기간)"
    end

    # Parse program weeks from duration string like "8주", "12주"
    def parse_program_weeks(duration, default)
      return default if duration.blank?

      match = duration.match(/(\d+)\s*(?:주|weeks?)/)
      weeks = match ? match[1].to_i : default
      weeks.clamp(2, 24)
    end

    # Parse days_per_week from frequency string like "주 3회", "주 3회, 1시간", "3일"
    def parse_days_per_week(frequency, default)
      return default if frequency.blank?

      match = frequency.match(/(\d+)\s*(?:회|일|번|days?)/)
      days = match ? match[1].to_i : default
      days.clamp(1, 7)
    end

    # Ensure LLM-generated split_schedule has exactly days_per_week training days
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
