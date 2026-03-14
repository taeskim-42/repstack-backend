# frozen_string_literal: true

# Extracted from ChatRoutineFormatter: long-term plan construction,
# weekly split logic, progression strategy, and goal timeline.
module ChatRoutineFormatter
  module LongTermPlanBuilder
    extend ActiveSupport::Concern

    private

    def build_long_term_plan(profile, consultation_data)
      tier = profile&.tier || "beginner"
      goal = profile&.fitness_goal || "건강"
      frequency = consultation_data["frequency"] || "주 3회"
      focus_areas = consultation_data["focus_areas"]

      freq_match = frequency.match(/(\d+)/)
      days_per_week = freq_match ? freq_match[1].to_i : 3
      days_per_week = [ [ days_per_week, 2 ].max, 6 ].min

      weekly_split = build_weekly_split(tier, days_per_week, focus_areas)
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
        build_beginner_split(days_per_week)
      when "intermediate"
        build_intermediate_split(days_per_week)
      when "advanced"
        build_advanced_split(days_per_week, focus_areas)
      else
        default_split
      end
    end

    def build_plan_description(tier, goal, _days_per_week)
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

    # Split builders per tier

    def build_beginner_split(days_per_week)
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
    end

    def build_intermediate_split(days_per_week)
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
        ppl_schedule(days_per_week)
      end
    end

    def build_advanced_split(days_per_week, focus_areas)
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
        ppl_schedule(days_per_week)
      end
    end

    def ppl_schedule(days_per_week)
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

    def default_split
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
end
