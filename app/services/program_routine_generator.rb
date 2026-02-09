# frozen_string_literal: true

# Generates all weekly routines for a TrainingProgram in bulk
# Called asynchronously after program creation via ProgramRoutineGenerateJob
#
# Strategy:
# - One LLM call per week (no Tool Use, exercise pool in prompt)
# - Each call generates all training days for that week
# - Saves to workout_routines + routine_exercises with generation_source: "program_baseline"
class ProgramRoutineGenerator
  VARIABLE_GUIDELINES = AiTrainer::ToolBasedRoutineGenerator::VARIABLE_GUIDELINES

  def initialize(user:, program:)
    @user = user
    @program = program
    @level = user.user_profile&.numeric_level || 1
    @tier = AiTrainer::Constants.tier_for_level(@level) || "beginner"
  end

  def generate_all
    failed_weeks = []
    (1..@program.total_weeks).each do |week|
      generate_week(week)
    rescue StandardError => e
      Rails.logger.error("[ProgramRoutineGenerator] Week #{week} failed: #{e.message}")
      failed_weeks << week
    end

    if failed_weeks.any?
      Rails.logger.error("[ProgramRoutineGenerator] Failed weeks: #{failed_weeks.join(', ')} for program #{@program.id}")
    end
  end

  def generate_week(week_number)
    # Skip if already generated (idempotent for retries)
    existing = @user.workout_routines.where(
      training_program_id: @program.id,
      week_number: week_number,
      generation_source: "program_baseline"
    )
    if existing.exists?
      Rails.logger.info("[ProgramRoutineGenerator] Week #{week_number} already generated, skipping")
      return
    end

    phase_info = @program.phase_info_for_week(week_number)
    training_days = @program.training_days

    return if training_days.empty?

    exercise_pool = build_exercise_pool(training_days)
    prompt = build_week_prompt(week_number, phase_info, training_days, exercise_pool)

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :routine_generation,
      system: system_prompt
    )

    if response[:success]
      save_week_routines(week_number, training_days, response[:content])
      Rails.logger.info("[ProgramRoutineGenerator] Week #{week_number} generated for program #{@program.id}")
    else
      Rails.logger.error("[ProgramRoutineGenerator] LLM failed for week #{week_number}: #{response[:error]}")
      raise "LLM call failed for week #{week_number}: #{response[:error]}"
    end
  end

  private

  def system_prompt
    variables = VARIABLE_GUIDELINES[@tier.to_sym] || VARIABLE_GUIDELINES[:beginner]

    <<~SYSTEM
      당신은 전문 피트니스 트레이너입니다. 주어진 프로그램 정보를 바탕으로 한 주의 운동 루틴을 설계합니다.

      ## 트레이닝 변인 가이드라인 (#{@tier} 레벨)
      - 운동 수: #{variables[:exercises_count]}개
      - 세트 수: #{variables[:sets_per_exercise]}세트/운동
      - 반복 수: #{variables[:reps_range]}회
      - RPE 범위: #{variables[:rpe_range]}
      - 휴식 시간: #{variables[:rest_seconds]}초
      - 총 세트: #{variables[:total_sets]}세트
      - 템포: #{variables[:tempo]}
      - 무게 가이드: #{variables[:weight_guide]}
      - 진행 방식: #{variables[:progression]}
      - 참고: #{variables[:notes]}

      ## 규칙
      1. 반드시 제공된 운동 후보 풀에서만 운동을 선택하세요
      2. 각 운동일마다 해당 근육군에 맞는 운동을 배치하세요
      3. 복합 운동(컴파운드)을 먼저, 고립 운동(아이솔레이션)을 나중에 배치하세요
      4. volume_modifier를 반영하여 세트 수와 강도를 조절하세요
      5. 응답은 반드시 JSON만 출력하세요 (마크다운 코드 블록 없이)
    SYSTEM
  end

  def build_exercise_pool(training_days)
    all_muscles = training_days.flat_map { |d| d[:muscles] }.uniq
    pool = {}

    all_muscles.each do |muscle|
      exercises = Exercise.active.for_level(@level).for_muscle(muscle)
                          .order(:difficulty).limit(8)
      pool[muscle] = exercises.map do |ex|
        {
          id: ex.id,
          name: ex.display_name || ex.name,
          english_name: ex.english_name,
          difficulty: ex.difficulty,
          equipment: ex.equipment
        }
      end
    end

    pool
  end

  def build_week_prompt(week_number, phase_info, training_days, exercise_pool)
    phase_name = phase_info&.dig("phase") || "일반"
    theme = phase_info&.dig("theme") || "점진적 과부하"
    volume_modifier = (phase_info&.dig("volume_modifier") || 1.0).to_f

    days_description = training_days.map do |day|
      muscles_str = day[:muscles].join(", ")
      "  - Day #{day[:day_number]}: #{day[:focus]} (근육: #{muscles_str})"
    end.join("\n")

    pool_description = exercise_pool.map do |muscle, exercises|
      ex_list = exercises.map { |e| "#{e[:name]} (난이도:#{e[:difficulty]}, 장비:#{e[:equipment]&.join(',')})" }.join(", ")
      "  #{muscle}: #{ex_list}"
    end.join("\n")

    <<~PROMPT
      ## 프로그램 정보
      - 프로그램: #{@program.name}
      - 주차: #{week_number}/#{@program.total_weeks}주
      - 페이즈: #{phase_name}
      - 테마: #{theme}
      - 볼륨 조절: #{(volume_modifier * 100).round}%

      ## 이번 주 운동일
      #{days_description}

      ## 운동 후보 풀 (반드시 이 목록에서만 선택)
      #{pool_description}

      ## 출력 형식 (JSON)
      {
        "days": [
          {
            "day_number": 1,
            "estimated_duration": 50,
            "exercises": [
              {
                "name": "운동 이름 (후보 풀에서 정확히 복사)",
                "target_muscle": "chest",
                "sets": 4,
                "reps": "10",
                "rest_seconds": 90,
                "weight_guide": "체중의 60% 또는 구체적 가이드",
                "instructions": "핵심 폼 포인트 1-2줄"
              }
            ]
          }
        ]
      }

      볼륨 #{(volume_modifier * 100).round}%를 반영하여 #{training_days.size}일분의 루틴을 생성해주세요.
    PROMPT
  end

  def save_week_routines(week_number, training_days, llm_response)
    parsed = JSON.parse(extract_json(llm_response))
    days = parsed["days"]

    return if days.blank?

    days.each do |day_data|
      day_num = day_data["day_number"]
      day_info = training_days.find { |d| d[:day_number] == day_num }
      next unless day_info

      routine = @user.workout_routines.create!(
        training_program_id: @program.id,
        generation_source: "program_baseline",
        level: @tier,
        week_number: week_number,
        day_number: day_num,
        day_of_week: day_name(day_num),
        workout_type: day_info[:focus],
        estimated_duration: day_data["estimated_duration"] || 45,
        generated_at: Time.current
      )

      (day_data["exercises"] || []).each_with_index do |ex, idx|
        routine.routine_exercises.create!(
          exercise_name: ex["name"],
          order_index: idx,
          sets: ex["sets"] || 3,
          reps: ex["reps"],
          target_muscle: ex["target_muscle"],
          rest_duration_seconds: ex["rest_seconds"],
          how_to: ex["instructions"],
          weight_description: ex["weight_guide"]
        )
      rescue StandardError => e
        Rails.logger.error("[ProgramRoutineGenerator] Failed to add exercise '#{ex['name']}': #{e.message}")
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error("[ProgramRoutineGenerator] JSON parse error for week #{week_number}: #{e.message}")
    raise
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

  def day_name(day_number)
    %w[monday tuesday wednesday thursday friday saturday sunday][day_number - 1] || "unknown"
  end
end
