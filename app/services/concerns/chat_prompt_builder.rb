# frozen_string_literal: true

# Extracted from ChatService: system prompt, user prompt, tools definition,
# conversation context, and message loading.
module ChatPromptBuilder
  extend ActiveSupport::Concern

  private

  def build_user_prompt
    prompt = message

    # Add routine context if available
    if routine_id.present? && current_routine
      exercises = current_routine.routine_exercises.order(:order_index).map do |ex|
        "#{ex.order_index + 1}. #{ex.exercise_name} (#{ex.sets}세트 x #{ex.reps}회)"
      end.join("\n")

      prompt = <<~PROMPT
        [현재 루틴]
        #{exercises}

        [사용자 메시지]
        #{message}
      PROMPT
    end

    prompt
  end

  def system_prompt
    tier = user.user_profile&.tier || "beginner"
    level = user.user_profile&.level || 1
    today = Time.current
    day_names = %w[일 월 화 수 목 금 토]

    # Check if user has today's routine (for feedback vs condition distinction)
    has_today_routine = WorkoutRoutine.where(user_id: user.id)
                                       .where("created_at >= ?", Time.current.beginning_of_day)
                                       .exists?

    # Check if workout was recently completed
    workout_completed = user.user_profile&.fitness_factors&.dig("last_workout_completed_at").present? &&
                        Time.parse(user.user_profile.fitness_factors["last_workout_completed_at"]) > Time.current.beginning_of_day rescue false

    <<~SYSTEM
      당신은 전문 피트니스 AI 트레이너입니다.

      ## 현재 시간
      - 오늘: #{today.strftime('%Y년 %m월 %d일')} (#{day_names[today.wday]}요일)
      - 시간: #{today.strftime('%H:%M')}

      ## 사용자 정보
      - 레벨: #{level} (#{tier_korean(tier)})
      - 이름: #{user.name || '회원'}
      - 오늘 루틴 있음: #{has_today_routine ? '예' : '아니오'}
      - 오늘 운동 완료: #{workout_completed ? '예' : '아니오'}

      #{memory_context}

      ## 대화 맥락
      #{conversation_context_summary}

      ## 중요: Tool 사용 규칙
      다음 요청에는 **반드시** 해당 tool을 호출하세요. 텍스트로 직접 답변하지 마세요:

      1. 루틴/운동 프로그램 요청 → **generate_routine** tool 필수
         예: "루틴 만들어줘", "오늘 운동 뭐해", "등운동 루틴", "광배근 루틴"
         (컨디션 + 루틴 요청: "피곤한데 운동 뭐해" → generate_routine의 condition 파라미터 사용)

      2. 컨디션만 언급 (루틴 요청 없이) → **check_condition** tool 필수
         예: "피곤해", "오늘 컨디션 안좋아", "어깨가 아파"
         ※ 오늘 루틴이 없거나, 운동 시작 전 상태를 말할 때만 사용

      3. 운동 기록 요청 → **record_exercise** tool 필수
         예: "벤치프레스 60kg 8회", "스쿼트 10회 했어"

      4. 운동 교체 요청 → **replace_exercise** tool 필수 (routineId가 있을 때)
         예: "XX 말고 다른거", "XX 대신 다른 운동"

      5. 운동 추가 요청 → **add_exercise** tool 필수 (routineId가 있을 때)
         예: "XX도 넣어줘", "팔운동 더 하고싶어"

      6. 운동 삭제 요청 → **delete_exercise** tool 필수 (routineId가 있을 때)
         예: "XX 빼줘", "XX 삭제해줘", "XX 빼고 싶어"

      7. 운동 계획/프로그램 설명 요청 → **explain_long_term_plan** tool 필수
         예: "내 운동 계획 알려줘", "주간 스케줄", "어떻게 운동해야 해", "프로그램 설명해줘", "나 어떤 운동 하면 돼"

      8. 운동 완료 선언 → **complete_workout** tool 필수
         예: "운동 끝났어", "완료", "다 했어", "끝", "오늘 운동 끝", "done", "finished"

      9. 운동 피드백 제출 → **submit_feedback** tool 필수
         예: "적당했어", "힘들었어", "스쿼트가 어려웠어"
         ※ feedback_type: just_right(적당/긍정), too_easy(쉬움), too_hard(힘듦), specific(특정 운동)
         ※ 판단 기준: 오늘 루틴 있음 + 운동 완료됨 상태에서 짧은 반응은 피드백으로 처리

      ## Tool 선택 판단 기준
      - **오늘 루틴 있음 + 운동 완료됨** 상태에서 짧은 반응 → submit_feedback (피드백)
      - **오늘 루틴 없음** 또는 **운동 시작 전** 컨디션 언급 → check_condition (컨디션)
      - 대화 맥락을 보고 사용자의 의도를 파악하세요

      ## 일반 대화만 tool 없이 답변
      - 운동 지식 질문, 폼 체크 설명, 일반 인사 등
      - 단, "XX 말고", "XX 대신" 등 교체 요청은 반드시 replace_exercise 호출!

      ## 응답 스타일
      - 친근하고 격려하는 톤
      - 한국어로 응답
    SYSTEM
  end

  def available_tools
    tools = [
      {
        name: "generate_routine",
        description: "새로운 운동 루틴을 생성합니다. 사용자가 '루틴 줘', '오늘 운동 뭐해', '피곤한데 운동 뭐해' 등 루틴을 요청할 때 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            goal: {
              type: "string",
              description: "운동 목표 (예: 가슴, 등, 체중감량)"
            },
            condition: {
              type: "string",
              description: "사용자 컨디션 그대로 전달 (예: '피곤함', '어깨가 좀 아파', '컨디션 좋음')"
            }
          },
          required: []
        }
      },
      {
        name: "check_condition",
        description: "사용자의 컨디션을 파악하고 기록합니다. 사용자가 '피곤해', '컨디션 안좋아', '오늘 좀 힘들어', '잠을 못잤어', '어깨가 아파', '컨디션 좋아', '굿', '최고' 등 자신의 상태를 말할 때 사용합니다. 루틴 요청 없이 컨디션만 언급할 때 이 tool을 호출하세요.",
        input_schema: {
          type: "object",
          properties: {
            condition_text: {
              type: "string",
              description: "사용자가 말한 컨디션 상태 원문 (예: '피곤해', '어깨가 좀 아파', '굿')"
            }
          },
          required: %w[condition_text]
        }
      },
      {
        name: "record_exercise",
        description: "운동 기록을 저장합니다. 사용자가 '벤치프레스 60kg 8회', '스쿼트 10회 3세트 했어' 등 운동 수행 내용을 말할 때 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            exercise_name: {
              type: "string",
              description: "운동 이름 (예: 벤치프레스, 스쿼트)"
            },
            weight: {
              type: "number",
              description: "무게 (kg). 맨몸 운동이면 생략"
            },
            reps: {
              type: "integer",
              description: "반복 횟수"
            },
            sets: {
              type: "integer",
              description: "세트 수 (기본값: 1)"
            }
          },
          required: %w[exercise_name reps]
        }
      },
      {
        name: "explain_long_term_plan",
        description: "사용자의 장기 운동 계획을 설명합니다. '내 운동 계획 알려줘', '주간 스케줄', '어떻게 운동해야 해', '프로그램 설명해줘' 등의 요청에 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            detail_level: {
              type: "string",
              description: "설명 수준 (brief: 간단히, detailed: 자세히)"
            }
          },
          required: []
        }
      },
      {
        name: "complete_workout",
        description: "사용자가 오늘 운동을 완료했음을 기록합니다. '운동 끝났어', '완료', '다 했어', '끝', 'done', '오늘 운동 끝' 등의 요청에 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            notes: {
              type: "string",
              description: "운동에 대한 메모나 코멘트 (선택)"
            }
          },
          required: []
        }
      },
      {
        name: "submit_feedback",
        description: "운동 완료 후 피드백을 제출합니다. '적당했어', '좀 쉬웠어', '힘들었어', '강도 올려줘', '강도 낮춰줘', '좋았어', '스쿼트가 어려웠어' 등의 피드백에 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            feedback_text: {
              type: "string",
              description: "사용자가 말한 피드백 원문 (예: '적당했어', '힘들었어', '스쿼트가 어려웠어')"
            },
            feedback_type: {
              type: "string",
              enum: %w[just_right too_easy too_hard specific],
              description: "피드백 유형: just_right(적당), too_easy(쉬움), too_hard(힘듦), specific(특정 운동 언급)"
            }
          },
          required: %w[feedback_text feedback_type]
        }
      }
    ]

    # Add routine modification tools only if routine_id is present
    if routine_id.present?
      tools += [
        {
          name: "replace_exercise",
          description: "루틴에서 특정 운동을 다른 운동으로 교체합니다. '벤치 말고 다른 거', '이거 힘들어', '어깨 아파서 못해' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              exercise_name: {
                type: "string",
                description: "교체할 운동 이름"
              },
              reason: {
                type: "string",
                description: "교체 이유 (부상, 장비 없음 등)"
              }
            },
            required: %w[exercise_name]
          }
        },
        {
          name: "add_exercise",
          description: "루틴에 새 운동을 추가합니다. '팔운동 더 하고 싶어', '플랭크도 넣어줘' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              exercise_name: {
                type: "string",
                description: "추가할 운동 이름"
              },
              sets: {
                type: "integer",
                description: "세트 수 (기본값: 3)"
              },
              reps: {
                type: "integer",
                description: "반복 횟수 (기본값: 10)"
              }
            },
            required: %w[exercise_name]
          }
        },
        {
          name: "delete_exercise",
          description: "루틴에서 특정 운동을 삭제합니다. 'XX 빼줘', 'XX 삭제해줘' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              exercise_name: {
                type: "string",
                description: "삭제할 운동 이름"
              }
            },
            required: %w[exercise_name]
          }
        }
      ]
    end

    tools
  end

  # Pre-load recent 15 messages once, reused by multiple methods
  def load_recent_messages
    @recent_messages = ChatMessage.where(user_id: user.id)
                                  .order(created_at: :desc)
                                  .limit(15)
                                  .reverse
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Failed to load recent messages: #{e.message}")
    @recent_messages = []
  end

  # Build conversation context summary for system prompt (brief)
  def conversation_context_summary
    recent = @recent_messages&.last(5) || []
    return "새 대화입니다." if recent.empty?

    recent.map do |msg|
      role = msg.role == "user" ? "사용자" : "트레이너"
      "#{role}: #{msg.content.to_s.truncate(50)}"
    end.join("\n")
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Failed to build conversation context: #{e.message}")
    "대화 컨텍스트를 불러오지 못했습니다."
  end

  # Build full conversation history for messages array (better context)
  # This allows Claude to understand the full conversation flow
  def build_conversation_history
    return [] if @recent_messages.blank?

    @recent_messages.map do |msg|
      {
        role: msg.role == "user" ? "user" : "assistant",
        content: msg.content.to_s
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Failed to build conversation history: #{e.message}")
    []
  end

  def memory_context
    ConversationMemoryService.format_context(user) || ""
  end
end
