# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Handles initial user level assessment through conversational AI
  # Routes to cost-efficient models via LLM Gateway
  # Automatically triggered for new users without level_assessed_at
  class LevelAssessmentService
    include Constants

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

        # Need assessment if level_assessed_at is nil
        profile.level_assessed_at.nil?
      end
    end

    def initialize(user:)
      @user = user
      @profile = user.user_profile || user.create_user_profile!
    end

    def assess(message)
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
      else
        save_assessment_state(result[:next_state], result[:collected_data])
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
        당신은 **웨이트 트레이닝(헬스) 전문** AI 트레이너입니다. 새로운 회원의 웨이트 트레이닝 수준을 파악하고 있습니다.

        ## 중요: 서비스 범위
        - 이 앱은 **웨이트 트레이닝(헬스장 운동) 전용**입니다
        - 지원: 벤치프레스, 스쿼트, 데드리프트, 덤벨/바벨 운동, 머신 운동, 맨몸 근력 운동
        - 미지원: 달리기, 수영, 자전거, 요가, 필라테스 등 유산소/비웨이트 운동
        - 사용자가 달리기 등 미지원 운동을 언급하면: "저희 앱은 웨이트 트레이닝 전문이에요! 헬스장에서 하는 근력 운동 루틴을 도와드릴게요 💪" 라고 안내하고 웨이트 트레이닝으로 자연스럽게 유도하세요

        ## 목표
        자연스러운 대화를 통해 사용자의 **웨이트 트레이닝** 경험과 수준을 파악합니다.

        ## 파악해야 할 정보
        1. 운동 경험 (experience): 헬스장/웨이트 트레이닝 경력
        2. 운동 빈도 (frequency): 주 몇 회 웨이트 운동하는지/할 수 있는지
        3. 운동 목표 (goals): 근비대, 근력 향상, 바디프로필 등 (웨이트 관련 목표)
        4. 제한사항 (limitations): 부상, 통증, 시간 제약 등 (선택)
        5. 현재 수준 지표 (strength_indicators): 3대 운동(벤치/스쿼트/데드) 무게 또는 맨몸운동 횟수

        ## 현재 상태
        - 대화 단계: #{current_state}
        - 수집된 정보: #{collected.to_json}

        ## 규칙
        1. 한 번에 1-2개의 질문만 하세요
        2. 친근하고 격려하는 톤을 유지하세요
        3. 답변은 2-4문장으로 간결하게
        4. 이모지를 적절히 사용하세요
        5. 정보가 충분히 모이면 수준을 판정하세요
        6. **절대로 달리기, 수영 등 웨이트 트레이닝 외의 운동 루틴을 제공하겠다고 하지 마세요**

        ## 응답 형식 (JSON)
        {
          "message": "사용자에게 보여줄 메시지",
          "next_state": "다음 대화 단계",
          "collected_data": {
            "experience": "파악된 경험 수준",
            "frequency": "주 운동 횟수",
            "goals": ["목표1", "목표2"],
            "limitations": ["제한사항"],
            "strength_indicators": {"bench": 60, "squat": 80, "deadlift": 100}
          },
          "is_complete": false,
          "assessment": null
        }

        수준 파악이 완료되면:
        {
          "message": "수준 파악 완료 메시지",
          "next_state": "completed",
          "collected_data": {...},
          "is_complete": true,
          "assessment": {
            "experience_level": "beginner|intermediate|advanced",
            "numeric_level": 1-8,
            "fitness_goal": "주요 목표",
            "summary": "사용자 수준 요약"
          }
        }

        ## 수준 판정 기준
        - beginner (1-2): 운동 경험 6개월 미만, 기본 동작 학습 필요
        - intermediate (3-5): 6개월-2년 경험, 기본기 있음, 3대 운동 가능
        - advanced (6-8): 2년 이상 경험, 고급 테크닉 가능
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

          {
            message: data["message"],
            next_state: data["next_state"] || STATES[:asking_experience],
            collected_data: new_collected,
            is_complete: data["is_complete"] || false,
            assessment: data["assessment"]
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

      profile.update!(
        numeric_level: assessment["numeric_level"] || 1,
        current_level: assessment["experience_level"] || "beginner",
        fitness_goal: assessment["fitness_goal"],
        level_assessed_at: Time.current,
        fitness_factors: profile.fitness_factors.merge(
          "assessment_summary" => assessment["summary"],
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
          "numeric_level" => 3,
          "fitness_goal" => "근비대",
          "summary" => "중급자, 주 3회 운동 가능, 근비대 목표"
        })
        {
          success: true,
          message: "수준 파악 완료! 🎉 중급자로 시작하시면 될 것 같아요. 이제 맞춤 루틴을 만들어드릴게요!",
          is_complete: true,
          assessment: {
            "experience_level" => "intermediate",
            "numeric_level" => 3,
            "fitness_goal" => "근비대"
          }
        }
      end
    end
  end
end
