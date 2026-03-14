# frozen_string_literal: true

# Extracted from ChatPromptBuilder: tool schema definitions for LLM tool use.
module ChatPromptBuilder
  module ToolDefinitions
    extend ActiveSupport::Concern

    private

    def available_tools
      tools = base_tools
      tools += routine_modification_tools if routine_id.present?
      tools
    end

    def base_tools
      [
        {
          name: "generate_routine",
          description: "새로운 운동 루틴을 생성합니다. 사용자가 '루틴 줘', '오늘 운동 뭐해', '피곤한데 운동 뭐해' 등 루틴을 요청할 때 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              goal: { type: "string", description: "운동 목표 (예: 가슴, 등, 체중감량)" },
              condition: { type: "string", description: "사용자 컨디션 그대로 전달 (예: '피곤함', '어깨가 좀 아파', '컨디션 좋음')" }
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
              condition_text: { type: "string", description: "사용자가 말한 컨디션 상태 원문 (예: '피곤해', '어깨가 좀 아파', '굿')" }
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
              exercise_name: { type: "string", description: "운동 이름 (예: 벤치프레스, 스쿼트)" },
              weight: { type: "number", description: "무게 (kg). 맨몸 운동이면 생략" },
              reps: { type: "integer", description: "반복 횟수" },
              sets: { type: "integer", description: "세트 수 (기본값: 1)" }
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
              detail_level: { type: "string", description: "설명 수준 (brief: 간단히, detailed: 자세히)" }
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
              notes: { type: "string", description: "운동에 대한 메모나 코멘트 (선택)" }
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
              feedback_text: { type: "string", description: "사용자가 말한 피드백 원문 (예: '적당했어', '힘들었어', '스쿼트가 어려웠어')" },
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
    end

    def routine_modification_tools
      [
        {
          name: "replace_exercise",
          description: "루틴에서 특정 운동을 다른 운동으로 교체합니다. '벤치 말고 다른 거', '이거 힘들어', '어깨 아파서 못해' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              exercise_name: { type: "string", description: "교체할 운동 이름" },
              reason: { type: "string", description: "교체 이유 (부상, 장비 없음 등)" }
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
              exercise_name: { type: "string", description: "추가할 운동 이름" },
              sets: { type: "integer", description: "세트 수 (기본값: 3)" },
              reps: { type: "integer", description: "반복 횟수 (기본값: 10)" }
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
              exercise_name: { type: "string", description: "삭제할 운동 이름" }
            },
            required: %w[exercise_name]
          }
        }
      ]
    end
  end
end
