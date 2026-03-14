# frozen_string_literal: true

module AiTrainer
  class ProgramGenerator
    # Default weekly plans, split schedules, and coach messages when LLM fails.
    # Depends on host class providing: @user
    module Defaults
      def default_weekly_plan(context)
        weeks = context[:default_weeks] || 8
        tier = context[:tier]

        # weeks is referenced only to document intent; tiers define their own ranges
        _ = weeks

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
          {
            "1" => { "focus" => "전신", "muscles" => %w[legs chest back shoulders core] },
            "3" => { "focus" => "전신", "muscles" => %w[legs chest back shoulders core] },
            "5" => { "focus" => "전신", "muscles" => %w[legs chest back shoulders core] }
          }
        when 3
          {
            "1" => { "focus" => "전신 A", "muscles" => %w[legs chest back] },
            "3" => { "focus" => "전신 B", "muscles" => %w[shoulders arms core] },
            "5" => { "focus" => "전신 C", "muscles" => %w[legs back shoulders] }
          }
        when 4
          {
            "1" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
            "2" => { "focus" => "하체", "muscles" => %w[legs core] },
            "4" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
            "5" => { "focus" => "하체", "muscles" => %w[legs core] }
          }
        when 5..6
          {
            "1" => { "focus" => "밀기 (Push)", "muscles" => %w[chest shoulders arms] },
            "2" => { "focus" => "당기기 (Pull)", "muscles" => %w[back arms] },
            "3" => { "focus" => "하체 (Legs)", "muscles" => %w[legs core] },
            "4" => { "focus" => "밀기 (Push)", "muscles" => %w[chest shoulders arms] },
            "5" => { "focus" => "당기기 (Pull)", "muscles" => %w[back arms] },
            "6" => { "focus" => "하체 (Legs)", "muscles" => %w[legs core] }
          }
        else
          {
            "1" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
            "2" => { "focus" => "하체", "muscles" => %w[legs core] },
            "4" => { "focus" => "상체", "muscles" => %w[chest back shoulders arms] },
            "5" => { "focus" => "하체", "muscles" => %w[legs core] }
          }
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

        { success: true, program: program, coach_message: default_coach_message(context) }
      end

      def default_coach_message(context)
        goal = context[:goal] || "건강한 몸"
        weeks = context[:default_weeks] || 8
        tier = context[:tier_korean] || "중급자"

        "#{context[:name]}님을 위한 #{weeks}주 #{goal} 프로그램을 준비했어요! " \
        "#{tier} 레벨에 맞게 점진적으로 난이도를 높여갈게요. " \
        "매일 컨디션과 피드백을 반영해서 최적의 루틴을 만들어드릴게요! 💪"
      end
    end
  end
end
