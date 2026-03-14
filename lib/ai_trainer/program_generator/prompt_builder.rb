# frozen_string_literal: true

module AiTrainer
  class ProgramGenerator
    # Builds system + user prompts for LLM-based program generation.
    # Depends on host class providing: @user, @profile, @collected_data
    module PromptBuilder
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

        user_prompt = build_user_context_prompt(context, rag_knowledge)

        { system: system_prompt, user: user_prompt }
      end

      private

      def build_user_context_prompt(context, rag_knowledge)
        <<~USER
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
      end

      def weeks_instruction(context)
        "위 정보를 바탕으로 **#{context[:default_weeks]}주** 장기 운동 프로그램 프레임워크를 JSON으로 생성해주세요.\n" \
        "⚠️ 사용자가 상담에서 희망한 기간(#{context[:default_weeks]}주)을 반드시 반영하세요!"
      end

      def weeks_note(context)
        "total_weeks는 반드시 #{context[:default_weeks]}주로 설정 (사용자가 상담에서 선택한 기간)"
      end
    end
  end # class ProgramGenerator
end
