# frozen_string_literal: true

# Extracted from ChatService: routine formatting, long-term plan building,
# weekly split, progression strategy, and routine DB persistence.
module ChatRoutineFormatter
  extend ActiveSupport::Concern

  private

  def format_routine_message(routine, program_info = nil)
    msg = "오늘의 루틴을 준비했어요! 💪\n\n"

    # Show program context if available
    if program_info
      phase = program_info[:phase] || program_info["phase"]
      week = program_info[:current_week] || program_info["current_week"]
      total = program_info[:total_weeks] || program_info["total_weeks"]
      if phase && week && total
        msg += "🗓️ **#{program_info[:name] || '프로그램'}** - #{week}/#{total}주차 (#{phase})\n"
      end
    end

    msg += "📋 **#{routine[:day_korean] || routine['day_korean']}** - #{routine[:fitness_factor_korean] || routine['fitness_factor_korean']}\n"
    msg += "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || routine['estimated_duration_minutes']}분\n\n"

    exercises = routine[:exercises] || routine["exercises"] || []
    msg += "**운동 목록:**\n"
    exercises.first(5).each do |ex|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      msg += "• #{name} #{sets}세트 x #{reps}회\n"
    end

    msg += "• ... 외 #{exercises.length - 5}개\n" if exercises.length > 5
    msg += "\n운동 시작할 준비가 되면 알려주세요!"
    msg
  end

  def format_regenerated_routine_message(routine)
    exercises = routine.routine_exercises.order(:order_index)

    msg = "**운동 목록:**\n"
    exercises.first(5).each do |ex|
      msg += "• #{ex.exercise_name} #{ex.sets}세트 x #{ex.reps}회\n"
    end

    msg += "• ... 외 #{exercises.length - 5}개\n" if exercises.length > 5
    msg += "\n운동 시작할 준비가 되면 알려주세요!"
    msg
  end

  def format_routine_for_display(routine)
    return "루틴을 준비하지 못했어요." unless routine

    lines = []
    lines << "📋 **#{routine[:day_korean] || '오늘의 루틴'}**"
    lines << "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || 60}분"
    lines << ""

    exercises = routine[:exercises] || []
    exercises.each_with_index do |ex, i|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      lines << "#{i + 1}. **#{name}** - #{sets}세트 x #{reps}회"
    end

    lines << ""
    lines << "준비되면 '운동 시작'이라고 말씀해주세요! 🔥"

    lines.join("\n")
  end

  def format_long_term_plan_message(long_term_plan, profile)
    name = user.name || "회원"
    goal = profile.fitness_goal || "건강"
    tier = tier_korean(profile.tier || "beginner")

    msg = "## 📋 #{name}님의 맞춤 운동 계획\n\n"
    msg += "**🎯 목표:** #{goal}\n"
    msg += "**💪 레벨:** #{tier}\n"
    msg += "**📅 주간 스케줄:** #{long_term_plan[:weekly_split]}\n\n"

    msg += "### 🗓️ 주간 운동 스케줄\n"
    long_term_plan[:weekly_schedule]&.each do |day|
      day_names = %w[일 월 화 수 목 금 토]
      day_name = day_names[day[:day]] || "#{day[:day]}일"
      msg += "- **#{day_name}요일:** #{day[:focus]}\n"
    end

    msg += "\n### 📈 훈련 전략\n"
    msg += "#{long_term_plan[:description]}\n\n"

    msg += "### 🔥 점진적 과부하\n"
    msg += "#{long_term_plan[:progression_strategy]}\n\n"

    msg += "### ⏰ 예상 결과\n"
    msg += "#{long_term_plan[:estimated_timeline]}\n\n"

    msg += "오늘 운동을 시작해볼까요? \"오늘 루틴 만들어줘\"라고 말씀해주세요! 💪"
    msg
  end

  def format_first_routine_message(routine)
    msg = "## 🎯 오늘의 첫 루틴이 준비됐어요!\n\n"
    msg += "📋 **#{routine[:day_korean] || routine['day_korean']}** - #{routine[:fitness_factor_korean] || routine['fitness_factor_korean'] || '맞춤 훈련'}\n"
    msg += "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || routine['estimated_duration_minutes'] || 45}분\n\n"

    exercises = routine[:exercises] || routine["exercises"] || []
    msg += "**운동 목록:**\n"
    exercises.each_with_index do |ex, idx|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      work_seconds = ex[:work_seconds] || ex["work_seconds"]

      if work_seconds.present?
        msg += "#{idx + 1}. #{name} - #{sets}세트 x #{work_seconds}초\n"
      else
        msg += "#{idx + 1}. #{name} - #{sets}세트 x #{reps}회\n"
      end
    end

    # Add coach message if available
    if routine[:notes].present? && routine[:notes].any?
      msg += "\n💡 **코치 팁:** #{routine[:notes].first}"
    end

    msg += "\n\n준비되면 \"운동 시작\"이라고 말씀해주세요! 함께 해볼까요? 💪"
    msg
  end

  # Convert existing DB routine to frontend format
  def format_existing_routine(routine)
    exercises = routine.routine_exercises.order(:order_index).map do |ex|
      {
        exercise_id: ex.id.to_s,
        exercise_name: ex.exercise_name,
        exercise_name_english: ex.exercise_name_english,
        target_muscle: ex.target_muscle,
        target_muscle_korean: ex.target_muscle_korean,
        order: ex.order_index + 1,
        sets: ex.sets,
        reps: ex.reps,
        target_weight_kg: ex.weight,
        weight_description: ex.weight_description,
        rest_seconds: ex.rest_duration_seconds,
        instructions: ex.how_to,
        rpe: ex.rpe,
        tempo: ex.tempo,
        rom: ex.range_of_motion
      }
    end

    {
      routine_id: routine.id.to_s,
      day_of_week: routine.day_number,
      day_korean: routine.day_korean,
      tier: routine.level,
      user_level: routine.user_level || 1,
      fitness_factor: routine.workout_type,
      fitness_factor_korean: routine.workout_type,
      estimated_duration_minutes: routine.estimated_duration,
      generated_at: routine.created_at.iso8601,
      exercises: exercises,
      training_type: routine.workout_type
    }
  end

  def save_routine_to_db(result)
    today = Date.current
    program = user.active_training_program

    routine = WorkoutRoutine.create!(
      user_id: user.id,
      level: user.user_profile&.tier || "beginner",
      week_number: program&.current_week || 1,
      day_number: today.cwday,  # Day of week (1=Mon, 7=Sun)
      workout_type: result[:workout_type] || "full_body",
      day_of_week: result[:day_korean] || today.strftime("%A"),
      estimated_duration: result[:estimated_duration_minutes] || 45,
      generated_at: Time.current
    )

    result[:exercises].each_with_index do |ex, idx|
      RoutineExercise.create!(
        workout_routine_id: routine.id,
        exercise_id: ex[:exercise_id] || ex["exercise_id"],
        exercise_name: ex[:exercise_name] || ex["exercise_name"] || ex[:name] || ex["name"],
        sets: ex[:sets] || ex["sets"] || 3,
        reps: ex[:reps] || ex["reps"] || 10,
        order_index: idx + 1
      )
    end

    routine
  rescue => e
    Rails.logger.error("Failed to save routine: #{e.message}")
    nil
  end

  # ============================================
  # Long-Term Plan Builders
  # ============================================

  def build_long_term_plan(profile, consultation_data)
    tier = profile&.tier || "beginner"
    goal = profile&.fitness_goal || "건강"
    frequency = consultation_data["frequency"] || "주 3회"
    focus_areas = consultation_data["focus_areas"]

    # Parse frequency
    freq_match = frequency.match(/(\d+)/)
    days_per_week = freq_match ? freq_match[1].to_i : 3
    days_per_week = [[days_per_week, 2].max, 6].min  # Clamp between 2-6

    # Build weekly split based on frequency and level
    weekly_split = build_weekly_split(tier, days_per_week, focus_areas)

    # Build plan description
    description = build_plan_description(tier, goal, days_per_week)

    {
      tier: tier,
      goal: goal,
      days_per_week: days_per_week,
      weekly_split: weekly_split[:description],
      weekly_schedule: weekly_split[:schedule],
      description: description,
      progression_strategy: build_progression_strategy(tier),
      estimated_timeline: estimate_goal_timeline(tier, goal)
    }
  end

  def build_weekly_split(tier, days_per_week, focus_areas)
    case tier
    when "beginner"
      if days_per_week <= 3
        {
          description: "전신 운동 (주 #{days_per_week}회)",
          schedule: (1..days_per_week).map { |d| { day: d, focus: "전신", muscles: %w[legs chest back shoulders core] } }
        }
      else
        {
          description: "상하체 분할 (주 #{days_per_week}회)",
          schedule: (1..days_per_week).map { |d| d.odd? ? { day: d, focus: "상체", muscles: %w[chest back shoulders arms] } : { day: d, focus: "하체", muscles: %w[legs core] } }
        }
      end
    when "intermediate"
      if days_per_week <= 4
        {
          description: "상하체 분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "상체", muscles: %w[chest back shoulders arms] },
            { day: 2, focus: "하체", muscles: %w[legs core] },
            { day: 3, focus: "상체", muscles: %w[chest back shoulders arms] },
            { day: 4, focus: "하체", muscles: %w[legs core] }
          ].first(days_per_week)
        }
      else
        {
          description: "PPL 분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] },
            { day: 2, focus: "당기기 (Pull)", muscles: %w[back biceps] },
            { day: 3, focus: "하체 (Legs)", muscles: %w[legs core] },
            { day: 4, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] },
            { day: 5, focus: "당기기 (Pull)", muscles: %w[back biceps] },
            { day: 6, focus: "하체 (Legs)", muscles: %w[legs core] }
          ].first(days_per_week)
        }
      end
    when "advanced"
      if days_per_week >= 5
        {
          description: "5분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "가슴", muscles: %w[chest] },
            { day: 2, focus: "등", muscles: %w[back] },
            { day: 3, focus: "어깨", muscles: %w[shoulders] },
            { day: 4, focus: "하체", muscles: %w[legs] },
            { day: 5, focus: "팔", muscles: %w[biceps triceps] },
            { day: 6, focus: "약점 보완", muscles: focus_areas&.split(",")&.map(&:strip) || %w[core] }
          ].first(days_per_week)
        }
      else
        {
          description: "PPL 분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] },
            { day: 2, focus: "당기기 (Pull)", muscles: %w[back biceps] },
            { day: 3, focus: "하체 (Legs)", muscles: %w[legs core] },
            { day: 4, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] }
          ].first(days_per_week)
        }
      end
    else
      {
        description: "전신 운동 (주 3회)",
        schedule: [
          { day: 1, focus: "전신", muscles: %w[legs chest back shoulders core] },
          { day: 2, focus: "전신", muscles: %w[legs chest back shoulders core] },
          { day: 3, focus: "전신", muscles: %w[legs chest back shoulders core] }
        ]
      }
    end
  end

  def build_plan_description(tier, goal, days_per_week)
    goal_strategies = {
      "근비대" => "근육량 증가를 위해 중량을 점진적으로 늘리고, 8-12회 반복에 집중합니다.",
      "다이어트" => "체지방 감소를 위해 서킷 트레이닝과 고반복 운동을 병행합니다.",
      "체력 향상" => "전반적인 체력 증진을 위해 복합 운동과 유산소를 균형있게 배치합니다.",
      "건강" => "건강 유지를 위해 모든 근육군을 균형있게 훈련합니다.",
      "strength" => "근력 향상을 위해 무거운 무게로 낮은 반복수(3-6회)에 집중합니다."
    }

    tier_approaches = {
      "beginner" => "기본 동작을 완벽히 익히는 것이 우선입니다. 가벼운 무게로 자세를 잡고, 2-3개월 후 무게를 늘려갑니다.",
      "intermediate" => "이제 점진적 과부하가 핵심입니다. 매주 조금씩 무게나 반복 수를 늘려가세요.",
      "advanced" => "주기화 훈련으로 근력과 근비대를 번갈아 집중합니다. 디로드 주간도 중요합니다."
    }

    strategy = goal_strategies[goal] || goal_strategies["건강"]
    approach = tier_approaches[tier] || tier_approaches["beginner"]

    "#{strategy} #{approach}"
  end

  def build_progression_strategy(tier)
    case tier
    when "beginner"
      "처음 4-6주: 동작 학습 기간 → 이후 매주 2.5% 또는 1-2회 증가"
    when "intermediate"
      "주당 2.5-5% 무게 증가, 4주마다 디로드 주간 포함"
    when "advanced"
      "3주 증가 + 1주 디로드 사이클, 비선형 주기화 적용"
    else
      "매주 조금씩 무게 또는 반복 수를 늘려가세요"
    end
  end

  def estimate_goal_timeline(tier, goal)
    base_weeks = case goal
    when "근비대" then 12
    when "다이어트" then 8
    when "체력 향상" then 6
    when "건강" then "지속적"
    else 8
    end

    tier_modifier = case tier
    when "beginner" then 1.5
    when "intermediate" then 1.0
    when "advanced" then 0.8
    else 1.0
    end

    if base_weeks.is_a?(Integer)
      adjusted = (base_weeks * tier_modifier).round
      "약 #{adjusted}주 후 눈에 띄는 변화 기대"
    else
      "꾸준히 운동하면 건강 유지 가능"
    end
  end

  def tier_korean(tier)
    { "none" => "입문", "beginner" => "초급", "intermediate" => "중급", "advanced" => "고급" }[tier] || "입문"
  end
end
