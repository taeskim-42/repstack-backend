# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Analyzes workout feedback from natural language text
  # Routes to cost-efficient models via LLM Gateway
  # Stores feedback for future routine personalization
  class FeedbackService
    include Constants

    class << self
      # For ChatService - returns chat-friendly response
      def analyze_from_text(user:, text:, routine_id: nil)
        new(user: user).analyze_from_text(text, routine_id: routine_id)
      end

      # For SubmitFeedback mutation - structured input
      def analyze_from_input(user:, input:)
        new(user: user).analyze_from_input(input)
      end

      # For SubmitFeedbackFromVoice mutation - voice input with feedback parsing
      def analyze_from_voice(user:, text:, routine_id: nil)
        new(user: user).analyze_from_voice(text, routine_id: routine_id)
      end
    end

    def initialize(user:)
      @user = user
    end

    def analyze_from_text(text, routine_id: nil)
      prompt = build_prompt(text)
      response = LlmGateway.chat(prompt: prompt, task: :feedback_analysis)

      if response[:success]
        parse_and_save_response(response[:content], text, routine_id)
      else
        mock_response
      end
    rescue StandardError => e
      Rails.logger.error("FeedbackService error: #{e.message}")
      { success: false, error: "피드백 분석 실패: #{e.message}" }
    end

    # For SubmitFeedback mutation - structured input returns analysis
    def analyze_from_input(input)
      prompt = build_input_prompt(input)
      response = LlmGateway.chat(prompt: prompt, task: :feedback_analysis)

      if response[:success]
        parse_input_response(response[:content])
      else
        mock_input_response(input)
      end
    rescue StandardError => e
      Rails.logger.error("FeedbackService.analyze_from_input error: #{e.message}")
      { success: false, error: "피드백 분석 실패: #{e.message}" }
    end

    # For SubmitFeedbackFromVoice mutation - voice input returns feedback + analysis
    def analyze_from_voice(text, routine_id: nil)
      prompt = build_voice_prompt(text, routine_id)
      response = LlmGateway.chat(prompt: prompt, task: :feedback_analysis)

      if response[:success]
        parse_voice_response(response[:content])
      else
        mock_voice_response(text)
      end
    rescue StandardError => e
      Rails.logger.error("FeedbackService.analyze_from_voice error: #{e.message}")
      { success: false, error: "음성 피드백 분석 실패: #{e.message}" }
    end

    private

    attr_reader :user

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

    def parse_and_save_response(response_text, original_text, routine_id)
      json_str = extract_json(response_text)
      data = JSON.parse(json_str)

      # Save feedback to database
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

    def save_feedback(data, original_text, routine_id)
      user.workout_feedbacks.create!(
        feedback: original_text,
        feedback_type: data["feedback_type"] || "general",
        rating: data["rating"] || 3,
        suggestions: data["adaptations"] || [],
        routine_id: routine_id,
        would_recommend: (data["rating"] || 3) >= 3
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("FeedbackService: Failed to save feedback: #{e.message}")
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

    # === analyze_from_input helpers ===

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
        insights: ["피드백을 다시 입력해주세요"],
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

      {
        success: true,
        insights: insights,
        adaptations: adaptations,
        next_workout_recommendations: recommendations
      }
    end

    # === analyze_from_voice helpers ===

    def build_voice_prompt(text, routine_id)
      <<~PROMPT
        You are an expert fitness coach. The user provides workout feedback via voice.
        Analyze their feedback and provide insights for future workouts.

        User's voice feedback (Korean or English):
        "#{text}"

        #{routine_id ? "Routine ID: #{routine_id}" : ""}

        Based on what the user said, determine:
        1. Overall satisfaction (rating 1-5)
        2. Feedback type (DIFFICULTY, SATISFACTION, PROGRESS, EXERCISE_SPECIFIC, GENERAL)
        3. Key insights from their feedback
        4. Adaptations for future workouts
        5. Specific recommendations for the next workout

        Respond ONLY with valid JSON in this exact format:
        ```json
        {
          "feedback": {
            "rating": 1-5,
            "feedbackType": "DIFFICULTY" or "SATISFACTION" or "PROGRESS" or "EXERCISE_SPECIFIC" or "GENERAL",
            "summary": "Brief summary of the feedback",
            "wouldRecommend": true or false
          },
          "insights": ["insight1", "insight2"],
          "adaptations": ["adaptation1", "adaptation2"],
          "nextWorkoutRecommendations": ["recommendation1", "recommendation2"],
          "interpretation": "Brief explanation of how you interpreted the feedback"
        }
        ```
      PROMPT
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
        feedback: {
          rating: 3,
          feedback_type: "GENERAL",
          summary: nil,
          would_recommend: true
        },
        insights: [],
        adaptations: [],
        next_workout_recommendations: [],
        interpretation: "피드백을 잘 이해하지 못했어요. 다시 한번 말씀해 주시겠어요?",
        needs_retry: true
      }
    end

    def mock_voice_response(text)
      # Simple rule-based fallback when LLM fails
      text_lower = text.downcase

      rating = 3
      feedback_type = "GENERAL"
      insights = []
      adaptations = []

      is_korean = text.match?(/[가-힣]/)

      # Difficulty detection
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

      # Satisfaction detection
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

      # Pain detection
      if text_lower.match?(/통증|아파|아픔|pain|hurt/)
        insights << (is_korean ? "통증이 있었습니다" : "Pain was reported")
        adaptations << "해당 부위 운동을 줄이세요"
      end

      insights << "피드백을 확인했습니다" if insights.empty?

      {
        success: true,
        feedback: {
          rating: rating,
          feedback_type: feedback_type,
          summary: text,
          would_recommend: rating >= 3
        },
        insights: insights,
        adaptations: adaptations,
        next_workout_recommendations: [],
        interpretation: "피드백을 분석했습니다."
      }
    end
  end
end
