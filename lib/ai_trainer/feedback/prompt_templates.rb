# frozen_string_literal: true

module AiTrainer
  module Feedback
    module PromptTemplates
      private

      def build_prompt(text)
        <<~PROMPT
          당신은 전문 피트니스 트레이너입니다. 사용자의 운동 피드백을 분석하세요.

          사용자 피드백: "#{text}"

          피드백을 분석하고 다음 루틴 생성에 반영할 정보를 추출하세요:
          1. 어떤 운동이 힘들었거나 쉬웠는지
          2. 통증이나 불편함이 있었는지
          3. 운동 강도/볼륨이 적절했는지
          4. 다음 루틴에 어떤 조정이 필요한지

          반드시 아래 JSON 형식으로만 응답하세요:
          ```json
          {
            "feedback_type": "difficulty|pain|preference|general",
            "rating": 3,
            "insights": ["분석된 인사이트1", "분석된 인사이트2"],
            "adaptations": ["다음 루틴 적용사항1", "다음 루틴 적용사항2"],
            "next_workout_recommendations": ["대체 운동 추천", "강도 조절 방향"],
            "affected_exercises": ["런지", "스쿼트"],
            "affected_muscles": ["legs", "core"],
            "message": "사용자에게 전달할 친근한 응답 메시지"
          }
          ```

          feedback_type 값:
          - "difficulty": 난이도 관련 (힘들었다/쉬웠다)
          - "pain": 통증/불편함 관련
          - "preference": 선호도 관련 (좋았다/별로였다)
          - "general": 일반 피드백

          rating: 1-5 (1=매우 부정적, 5=매우 긍정적)
        PROMPT
      end

      def build_input_prompt(input)
        <<~PROMPT
          You are an expert fitness coach. Analyze this workout feedback and provide insights.

          Feedback:
          - Type: #{input[:feedback_type]}
          - Rating: #{input[:rating]}/5
          - Comments: #{input[:feedback]}
          - Would Recommend: #{input[:would_recommend]}
          - Suggestions: #{input[:suggestions]&.join(", ") || "None"}

          Respond ONLY with valid JSON in this exact format:
          ```json
          {
            "insights": ["insight1", "insight2"],
            "adaptations": ["adaptation1", "adaptation2"],
            "nextWorkoutRecommendations": ["recommendation1", "recommendation2"]
          }
          ```
        PROMPT
      end

      def build_voice_prompt(text, routine_id)
        <<~PROMPT
          당신은 친근하고 전문적인 피트니스 트레이너입니다. 사용자가 운동 완료 후 피드백을 보냈습니다.

          사용자 피드백:
          "#{text}"

          #{routine_id ? "루틴 ID: #{routine_id}" : ""}

          다음을 분석하세요:
          1. 전반적인 만족도 (1-5점)
          2. 피드백 유형 (DIFFICULTY, SATISFACTION, PROGRESS, EXERCISE_SPECIFIC, GENERAL)
          3. 피드백에서 얻은 인사이트
          4. 다음 운동에 적용할 조정사항
          5. 다음 운동을 위한 구체적인 추천

          **중요**: interpretation 필드에는 사용자에게 보여줄 **친근한 한국어 응답 메시지**를 작성하세요.
          - 운동 완료를 축하하고
          - 피드백에 공감하며
          - 다음 루틴에 어떻게 반영할지 간단히 언급
          - 2-3문장, 이모지 사용 OK

          반드시 아래 JSON 형식으로만 응답하세요:
          ```json
          {
            "feedback": {
              "rating": 1-5,
              "feedbackType": "DIFFICULTY" or "SATISFACTION" or "PROGRESS" or "EXERCISE_SPECIFIC" or "GENERAL",
              "summary": "피드백 요약",
              "wouldRecommend": true or false
            },
            "insights": ["인사이트1", "인사이트2"],
            "adaptations": ["다음 루틴 적용사항1", "다음 루틴 적용사항2"],
            "nextWorkoutRecommendations": ["추천1", "추천2"],
            "interpretation": "오늘 운동 수고하셨어요! 💪 [피드백에 맞는 친근한 응답]"
          }
          ```
        PROMPT
      end
    end
  end
end
