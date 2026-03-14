# frozen_string_literal: true

module AiTrainer
  module Feedback
    module ResponseParser
      private

      def parse_and_save_response(response_text, original_text, routine_id)
        json_str = extract_json(response_text)
        data = JSON.parse(json_str)

        save_feedback(data, original_text, routine_id)

        {
          success: true,
          message: data["message"],
          insights: data["insights"] || [],
          adaptations: data["adaptations"] || [],
          next_workout_recommendations: data["next_workout_recommendations"] || [],
          affected_exercises: data["affected_exercises"] || [],
          affected_muscles: data["affected_muscles"] || []
        }
      rescue JSON::ParserError => e
        Rails.logger.error("FeedbackService JSON parse error: #{e.message}")
        retry_feedback_response
      end

      def retry_feedback_response
        {
          success: true,
          message: "피드백을 잘 이해하지 못했어요. 다시 한번 말씀해 주시겠어요? 예: '오늘 운동 힘들었어요' 또는 '스쿼트가 좀 쉬웠어요'",
          insights: [],
          adaptations: [],
          next_workout_recommendations: [],
          needs_retry: true
        }
      end

      def mock_response
        {
          success: true,
          message: "피드백 감사해요! 다음 루틴에 반영할게요. 💡",
          insights: [ "피드백이 기록되었습니다" ],
          adaptations: [ "다음 루틴에 반영 예정" ],
          next_workout_recommendations: []
        }
      end

      def parse_input_response(response_text)
        json_str = extract_json(response_text)
        data = JSON.parse(json_str)

        {
          success: true,
          insights: data["insights"] || [],
          adaptations: data["adaptations"] || [],
          next_workout_recommendations: data["nextWorkoutRecommendations"] || []
        }
      rescue JSON::ParserError => e
        Rails.logger.error("FeedbackService parse_input_response error: #{e.message}")
        {
          success: true,
          insights: [ "피드백을 다시 입력해주세요" ],
          adaptations: [],
          next_workout_recommendations: [],
          needs_retry: true
        }
      end

      def mock_input_response(input)
        rating = input[:rating] || 3
        insights = []
        adaptations = []
        recommendations = []

        if rating >= 4
          insights << "운동이 효과적이었습니다"
          recommendations << "같은 강도로 계속하세요"
        elsif rating <= 2
          insights << "운동이 힘들었습니다"
          adaptations << "강도를 낮추는 것을 고려하세요"
          recommendations << "자세와 테크닉에 집중하세요"
        else
          insights << "적당한 만족도입니다"
          recommendations << "점진적으로 도전을 늘려보세요"
        end

        case input[:feedback_type]
        when "DIFFICULTY", "difficulty"
          adaptations << (rating > 3 ? "다음에 난이도를 높이세요" : "다음에 난이도를 낮추세요")
        when "TIME", "time"
          recommendations << (rating > 3 ? "운동 시간이 적절합니다" : "운동 시간을 조정하세요")
        end

        { success: true, insights: insights, adaptations: adaptations, next_workout_recommendations: recommendations }
      end

      def parse_voice_response(response_text)
        json_str = extract_json(response_text)
        data = JSON.parse(json_str)
        feedback = data["feedback"] || {}

        {
          success: true,
          feedback: {
            rating: feedback["rating"] || 3,
            feedback_type: feedback["feedbackType"] || "GENERAL",
            summary: feedback["summary"],
            would_recommend: feedback["wouldRecommend"] != false
          },
          insights: data["insights"] || [],
          adaptations: data["adaptations"] || [],
          next_workout_recommendations: data["nextWorkoutRecommendations"] || [],
          interpretation: data["interpretation"]
        }
      rescue JSON::ParserError => e
        Rails.logger.error("FeedbackService parse_voice_response error: #{e.message}")
        {
          success: true,
          feedback: { rating: 3, feedback_type: "GENERAL", summary: nil, would_recommend: true },
          insights: [],
          adaptations: [],
          next_workout_recommendations: [],
          interpretation: "피드백을 잘 이해하지 못했어요. 다시 한번 말씀해 주시겠어요?",
          needs_retry: true
        }
      end

      def mock_voice_response(text)
        text_lower = text.downcase
        rating = 3
        feedback_type = "GENERAL"
        insights = []
        adaptations = []
        is_korean = text.match?(/[가-힣]/)

        if text_lower.match?(/힘들|어려|tough|hard/)
          rating = 2
          feedback_type = "DIFFICULTY"
          insights << "Workout felt challenging"
          adaptations << "다음 운동 강도를 낮추세요"
        elsif text_lower.match?(/쉬웠|쉬워|easy/)
          rating = 4
          feedback_type = "DIFFICULTY"
          insights << (is_korean ? "운동이 쉬웠다고 느꼈습니다" : "Workout felt easy")
        end

        if text_lower.match?(/만족|좋았|좋아|great|good|positive/)
          rating = 4
          feedback_type = "SATISFACTION"
          insights << (is_korean ? "전반적으로 만족스러웠습니다" : "Overall satisfaction was positive")
        elsif text_lower.match?(/별로|싫|bad|불만/)
          rating = 2
          feedback_type = "SATISFACTION"
          insights << (is_korean ? "만족스럽지 않았습니다" : "Not satisfied")
          adaptations << "다음 운동 강도를 조절합니다"
        end

        if text_lower.match?(/통증|아파|아픔|pain|hurt/)
          insights << (is_korean ? "통증이 있었습니다" : "Pain was reported")
          adaptations << "해당 부위 운동을 줄이세요"
        end

        insights << "피드백을 확인했습니다" if insights.empty?

        interpretation = case rating
        when 1..2 then "오늘 운동 수고하셨어요! 💪 힘드셨군요. 다음 루틴은 조금 더 가볍게 조정해드릴게요. 푹 쉬세요! 🌙"
        when 4..5 then "오늘 운동 수고하셨어요! 💪 여유가 있으셨네요! 다음엔 더 도전적인 루틴으로 준비할게요. 화이팅! 🔥"
        else "오늘 운동 수고하셨어요! 💪 피드백 반영해서 다음 루틴을 더 좋게 만들어드릴게요!"
        end

        {
          success: true,
          feedback: { rating: rating, feedback_type: feedback_type, summary: text, would_recommend: rating >= 3 },
          insights: insights,
          adaptations: adaptations,
          next_workout_recommendations: [],
          interpretation: interpretation
        }
      end
    end
  end
end
