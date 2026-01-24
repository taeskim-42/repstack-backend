# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Handles initial user level assessment through conversational AI
  # Routes to cost-efficient models via LLM Gateway
  # Automatically triggered for new users without level_assessed_at
  class LevelAssessmentService
    include Constants

    # Prompt version for A/B testing and tracking
    PROMPT_VERSION = "v2.0-flexible"

    # Assessment conversation states
    STATES = {
      initial: "initial",
      asking_experience: "asking_experience",
      asking_frequency: "asking_frequency",
      asking_goals: "asking_goals",
      asking_limitations: "asking_limitations",
      completed: "completed"
    }.freeze

    class << self
      def assess(user:, message:)
        new(user: user).assess(message)
      end

      def needs_assessment?(user)
        profile = user.user_profile
        return true unless profile

        # Need assessment if onboarding not completed
        profile.onboarding_completed_at.nil?
      end
    end

    def initialize(user:)
      @user = user
      @profile = user.user_profile || user.create_user_profile!
    end

    def assess(message)
      # Get or create analytics record
      analytics = get_or_create_analytics

      # Get current assessment state from profile
      current_state = get_assessment_state

      # Build conversation history
      conversation = build_conversation(message, current_state)

      # Call LLM Gateway
      response = LlmGateway.chat(
        prompt: message,
        task: :level_assessment,
        messages: conversation[:messages],
        system: conversation[:system]
      )

      if response[:success]
        result = parse_response(response, message)
      else
        return mock_response
      end

      # Update profile if assessment is complete
      if result[:is_complete]
        update_profile_with_assessment(result[:assessment])
        complete_analytics(analytics, result[:collected_data], "user_ready")
      else
        save_assessment_state(result[:next_state], result[:collected_data])
        update_analytics(analytics, message, result)
      end

      {
        success: true,
        message: result[:message],
        is_complete: result[:is_complete],
        assessment: result[:is_complete] ? result[:assessment] : nil
      }
    rescue StandardError => e
      Rails.logger.error("LevelAssessmentService error: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      record_analytics_error(analytics, e.message) if analytics
      { success: false, message: "수준 파악 중 오류가 발생했습니다.", error: e.message }
    end

    private

    attr_reader :user, :profile

    def get_assessment_state
      profile.fitness_factors["assessment_state"] || STATES[:initial]
    end

    def get_collected_data
      profile.fitness_factors["collected_data"] || {}
    end

    def save_assessment_state(state, collected_data)
      current_factors = profile.fitness_factors || {}
      profile.update!(
        fitness_factors: current_factors.merge(
          "assessment_state" => state,
          "collected_data" => collected_data
        )
      )
    end

    def build_conversation(user_message, current_state)
      collected = get_collected_data

      system_prompt = <<~PROMPT
        당신은 **웨이트 트레이닝(헬스) 전문** AI 트레이너입니다. 새로운 회원과 온보딩 대화를 진행합니다.

        ## 목표
        사용자에 대해 **최대한 많은 정보**를 자연스럽게 수집하세요.
        더 많은 정보 = 더 정교한 맞춤 루틴 생성 가능!

        ## 서비스 범위
        - 이 앱은 **웨이트 트레이닝(헬스장 운동) 전용**입니다
        - 달리기, 수영 등 유산소 운동은 미지원

        ## 수집할 정보 (필수 3가지 + 선택)
        **필수:**
        1. 운동 경험 (experience): 헬스장 경력
        2. 운동 빈도 (frequency): 주 몇 회, 몇 시간
        3. 운동 목표 (goals): 근비대, 다이어트, 체력 향상 등

        **선택 (자연스럽게 파악되면 좋음):**
        - 부상/통증 이력 (injuries)
        - 선호하는 운동 (preferences)
        - 시간 제약 (time_constraints)
        - 운동 환경 (gym_access): 헬스장/홈트 등

        ## 현재 상태
        - 대화 단계: #{current_state}
        - 수집된 정보: #{collected.to_json}
        - 필수 정보 체크: experience=#{collected['experience'] ? '✓' : '✗'}, frequency=#{collected['frequency'] ? '✓' : '✗'}, goals=#{collected['goals'] ? '✓' : '✗'}
        → 3개 모두 ✓이면 완료 가능!

        ## 핵심 규칙
        1. **사용자가 질문하면 답변**하고 대화 계속
        2. 친근한 트레이너처럼 조언해주세요
        3. **필수 3가지(경험, 빈도, 목표)가 파악되면 완료 가능**
        4. 완료 시 "체력테스트" 언급 금지 (앱에서 CTA로 안내)

        ## 완료 타이밍 (중요!)
        ✅ **즉시 완료**: 경험 + 빈도 + 목표가 파악되고, 사용자가 마무리 신호를 보내면
           - 마무리 신호: "네", "알겠어요", "좋아요", "시작할게요", "그렇게 할게요" 등
        ✅ **완료 가능**: 필수 3가지가 파악되면 추가 질문 없이 완료해도 됨
        ❌ **계속 대화**: 사용자가 명확히 질문하거나 조언을 구할 때만

        ## 응답 형식 (JSON)
        {
          "message": "사용자에게 보여줄 메시지",
          "next_state": "conversing 또는 completed",
          "collected_data": {
            "experience": "파악된 경험",
            "frequency": "주 운동 횟수",
            "goals": "목표",
            "injuries": "부상 이력 (있으면)",
            "preferences": "선호 운동 (있으면)",
            "time_constraints": "시간 제약 (있으면)"
          },
          "is_complete": false,
          "assessment": null
        }

        ## 완료 응답 (experience, frequency, goals 모두 파악되면):
        {
          "message": "좋아요! 상황 파악됐어요. 💪",
          "next_state": "completed",
          "collected_data": {"experience": "...", "frequency": "...", "goals": "..."},
          "is_complete": true,
          "assessment": {
            "experience_level": "beginner|intermediate|advanced",
            "numeric_level": null,
            "fitness_goal": "주요 목표",
            "summary": "사용자 요약"
          }
        }

        ⚠️ 중요: experience, frequency, goals가 모두 파악되었고 사용자가 "네", "알겠어요", "좋아요" 등의 마무리 답변을 하면 반드시 is_complete: true로 응답하세요!

        ## 수준 판정
        - beginner: 초보, 6개월 미만
        - intermediate: 6개월~2년
        - advanced: 2년 이상 경험자
      PROMPT

      messages = []

      # Add initial greeting if first message
      if current_state == STATES[:initial]
        messages << {
          role: "assistant",
          content: "안녕하세요! 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 💪 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?"
        }
      end

      # Add conversation history from collected data (filter out empty content)
      if collected["conversation_history"].present?
        collected["conversation_history"].each do |turn|
          next if turn["content"].blank?
          messages << { role: turn["role"], content: turn["content"] }
        end
      end

      # Add current user message
      messages << { role: "user", content: user_message }

      { system: system_prompt, messages: messages }
    end

    def parse_response(llm_response, user_message)
      content = llm_response[:content]

      # Try to parse as JSON
      begin
        # Extract JSON from response (might be wrapped in markdown code blocks)
        json_match = content.match(/\{[\s\S]*\}/)
        if json_match
          data = JSON.parse(json_match[0])

          # Preserve conversation history
          collected = get_collected_data
          history = collected["conversation_history"] || []

          # Add current exchange to history (only non-empty messages)
          new_collected = data["collected_data"] || {}
          new_history = history.dup
          new_history << { "role" => "user", "content" => user_message } if user_message.present?
          new_history << { "role" => "assistant", "content" => data["message"] } if data["message"].present?
          new_collected["conversation_history"] = new_history

          # Ensure assessment always has numeric_level (nil until fitness test)
          assessment = data["assessment"]
          if assessment.is_a?(Hash)
            assessment = assessment.merge("numeric_level" => nil) unless assessment.key?("numeric_level")
          end

          {
            message: data["message"],
            next_state: data["next_state"] || STATES[:asking_experience],
            collected_data: new_collected,
            is_complete: data["is_complete"] || false,
            assessment: assessment
          }
        else
          # Fallback: treat as plain text response
          {
            message: content,
            next_state: STATES[:asking_experience],
            collected_data: get_collected_data,
            is_complete: false,
            assessment: nil
          }
        end
      rescue JSON::ParserError
        {
          message: content,
          next_state: STATES[:asking_experience],
          collected_data: get_collected_data,
          is_complete: false,
          assessment: nil
        }
      end
    end

    def update_profile_with_assessment(assessment)
      return unless assessment

      # Only save basic info from onboarding conversation
      # DO NOT set numeric_level or current_level here
      # Level will be set after fitness test completion
      profile.update!(
        fitness_goal: assessment["fitness_goal"],
        onboarding_completed_at: Time.current,
        fitness_factors: profile.fitness_factors.merge(
          "onboarding_assessment" => assessment,
          "assessment_state" => STATES[:completed]
        )
      )
    end

    def mock_response
      state = get_assessment_state

      case state
      when STATES[:initial]
        save_assessment_state(STATES[:asking_experience], {})
        {
          success: true,
          message: "안녕하세요! 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 💪 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?",
          is_complete: false,
          assessment: nil
        }
      when STATES[:asking_experience]
        save_assessment_state(STATES[:asking_frequency], { "experience" => "intermediate" })
        {
          success: true,
          message: "좋아요! 경험이 있으시네요. 💪 주로 몇 번 정도 운동하시나요?",
          is_complete: false,
          assessment: nil
        }
      when STATES[:asking_frequency]
        save_assessment_state(STATES[:asking_goals], { "experience" => "intermediate", "frequency" => 3 })
        {
          success: true,
          message: "주 3회 정도면 좋은 루틴을 짤 수 있어요! 운동 목표가 뭔가요? (근비대, 다이어트, 체력 향상 등)",
          is_complete: false,
          assessment: nil
        }
      else
        update_profile_with_assessment({
          "experience_level" => "intermediate",
          "fitness_goal" => "근비대",
          "summary" => "중급자, 주 3회 운동 가능, 근비대 목표"
        })
        {
          success: true,
          message: "좋아요! 대략적인 상황 파악됐어요. 💪",
          is_complete: true,
          assessment: {
            "experience_level" => "intermediate",
            "numeric_level" => nil,
            "fitness_goal" => "근비대",
            "summary" => "중급자, 주 3회 운동 가능, 근비대 목표"
          }
        }
      end
    end

    # Analytics methods
    def get_or_create_analytics
      session_id = get_session_id
      OnboardingAnalytics.find_or_create_by!(user: user, session_id: session_id) do |a|
        a.prompt_version = PROMPT_VERSION
        a.conversation_log = []
      end
    rescue ActiveRecord::RecordNotUnique
      OnboardingAnalytics.find_by(session_id: session_id)
    rescue StandardError => e
      Rails.logger.warn("Failed to create analytics: #{e.message}")
      nil
    end

    def get_session_id
      # Use date-based session to group conversations by day
      "onboarding-#{user.id}-#{Date.current}"
    end

    def update_analytics(analytics, user_message, result)
      return unless analytics

      analytics.turn_count += 1
      analytics.conversation_log << {
        turn: analytics.turn_count,
        user: user_message,
        assistant: result[:message],
        timestamp: Time.current.iso8601
      }
      analytics.collected_info = result[:collected_data] || {}
      analytics.save
    rescue StandardError => e
      Rails.logger.warn("Failed to update analytics: #{e.message}")
    end

    def complete_analytics(analytics, collected_data, reason)
      return unless analytics

      analytics.update(
        completed: true,
        completion_reason: reason,
        collected_info: collected_data || {},
        time_to_complete_seconds: (Time.current - analytics.created_at).to_i
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to complete analytics: #{e.message}")
    end

    def record_analytics_error(analytics, error_message)
      return unless analytics

      analytics.update(
        completion_reason: "error",
        collected_info: (analytics.collected_info || {}).merge("error" => error_message)
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to record analytics error: #{e.message}")
    end
  end
end
