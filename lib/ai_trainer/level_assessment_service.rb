# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"
require_relative "program_generator"

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
        return false unless profile

        # Need assessment if form onboarding is done but AI consultation is not
        profile.form_onboarding_completed_at.present? && profile.onboarding_completed_at.nil?
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

      # ============================================
      # FIRST GREETING: When user enters chat mode after form onboarding
      # AI should greet first with personalized message based on form data
      # ============================================
      if current_state == STATES[:initial] && (message.blank? || message == "start" || message == "시작")
        return handle_first_greeting(analytics)
      end

      # Check if API is configured - if not, use fallback mock_response
      unless LlmGateway.configured?(task: :level_assessment)
        Rails.logger.info("[LevelAssessmentService] Using mock response (API not configured)")
        result = mock_response(message)
        update_analytics(analytics, message, { message: result[:message], collected_data: get_collected_data })
        return result
      end

      # Always use Claude API for creative, natural responses

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
        # IMPORTANT: Save collected_data to DB BEFORE generating program
        # ProgramGenerator reads from DB, so data must be saved first!
        save_assessment_state(STATES[:completed], result[:collected_data])

        update_profile_with_assessment(result[:assessment])
        complete_analytics(analytics, result[:collected_data], "user_ready")

        # Auto-generate long-term training program after consultation complete
        program_result = generate_initial_routine(result[:collected_data])

        # Build completion message with program info
        completion_message = build_completion_message_with_routine(result[:message], program_result)

        return {
          success: true,
          message: completion_message,
          is_complete: true,
          assessment: result[:assessment],
          program: program_result[:program],  # TrainingProgram model instance
          suggestions: result[:suggestions]
        }
      else
        save_assessment_state(result[:next_state], result[:collected_data])
        update_analytics(analytics, message, result)
      end

      {
        success: true,
        message: result[:message],
        is_complete: result[:is_complete],
        assessment: result[:is_complete] ? result[:assessment] : nil,
        suggestions: result[:suggestions]
      }
    rescue StandardError => e
      Rails.logger.error("LevelAssessmentService error: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      record_analytics_error(analytics, e.message) if analytics
      { success: false, message: "수준 파악 중 오류가 발생했습니다.", error: e.message }
    end

    private

    attr_reader :user, :profile

    # Handle first greeting when user enters chat after form onboarding
    # Uses LLM to generate personalized greeting + contextual suggestions
    def handle_first_greeting(analytics)
      form_data = extract_form_data

      # Determine next state based on what's already known
      next_state = determine_next_state(form_data)

      # Save state with form data as initial collected data
      save_assessment_state(next_state, form_data)

      # Use LLM for first greeting (generates both message + suggestions)
      if LlmGateway.configured?(task: :level_assessment)
        greeting_instruction = "사용자가 처음 채팅에 들어왔습니다. 이미 파악된 정보를 확인했다고 언급하고, 첫 번째 질문을 해주세요."
        conversation = build_conversation(greeting_instruction, next_state)

        response = LlmGateway.chat(
          prompt: greeting_instruction,
          task: :level_assessment,
          messages: conversation[:messages],
          system: conversation[:system]
        )

        if response[:success]
          result = parse_response(response, "")
          update_analytics(analytics, "", { message: result[:message], collected_data: form_data })
          return {
            success: true,
            message: result[:message],
            is_complete: false,
            assessment: nil,
            suggestions: result[:suggestions]
          }
        end
      end

      # Fallback: hardcoded greeting (only if LLM fails or not configured)
      greeting = build_personalized_greeting(form_data)
      update_analytics(analytics, "", { message: greeting, collected_data: form_data })

      {
        success: true,
        message: greeting,
        is_complete: false,
        assessment: nil,
        suggestions: []
      }
    end

    # Build personalized greeting based on form data
    def build_personalized_greeting(form_data)
      name = user.name || "회원"
      goal = form_data["goals"] || profile.fitness_goal
      experience = form_data["experience"]
      
      greeting_parts = []
      greeting_parts << "#{name}님, 안녕하세요! 💪"
      
      # Acknowledge what we already know
      known_info = []
      known_info << "**#{goal}** 목표" if goal.present?
      known_info << "**#{translate_experience(experience)}** 수준" if experience.present?
      known_info << "키 **#{form_data['height']}cm**" if form_data["height"].present?
      known_info << "체중 **#{form_data['weight']}kg**" if form_data["weight"].present?
      
      if known_info.any?
        greeting_parts << ""
        greeting_parts << "입력해주신 정보를 확인했어요:"
        greeting_parts << known_info.map { |info| "- #{info}" }.join("\n")
      end
      
      # Explain what we need for better routine
      greeting_parts << ""
      greeting_parts << "더 정확한 맞춤 루틴을 위해 몇 가지만 더 여쭤볼게요! 😊"
      
      # Ask the first question based on what's missing
      missing_questions = determine_missing_questions(form_data)
      if missing_questions.any?
        greeting_parts << ""
        greeting_parts << missing_questions.first
      end
      
      greeting_parts.join("\n")
    end

    # Determine what questions to ask based on missing data
    def determine_missing_questions(form_data)
      questions = []
      
      if form_data["frequency"].blank?
        questions << "우선, **주에 몇 번, 한 번에 몇 시간** 정도 운동하실 수 있으세요?"
      end
      
      if form_data["environment"].blank?
        questions << "운동 환경은 어떻게 되세요? (헬스장/홈트/기구 유무)"
      end
      
      if form_data["injuries"].blank?
        questions << "혹시 부상이나 피해야 할 동작이 있으신가요?"
      end
      
      questions
    end

    # Determine next state based on what's already known
    def determine_next_state(form_data)
      if form_data["frequency"].blank?
        STATES[:asking_frequency]
      elsif form_data["goals"].blank?
        STATES[:asking_goals]
      elsif form_data["experience"].blank?
        STATES[:asking_experience]
      else
        "asking_environment"
      end
    end

    # Handle initial greeting using form_data directly (no LLM call needed)
    # Legacy method - kept for compatibility
    def handle_initial_greeting(analytics, message)
      form_data = extract_form_data
      greeting = build_initial_greeting(form_data)

      # Determine next state based on what we already know
      next_state = if form_data["experience"].present? && form_data["goals"].present?
                     STATES[:asking_frequency]
                   elsif form_data["experience"].present?
                     STATES[:asking_goals]
                   else
                     STATES[:asking_experience]
                   end

      # Save state with form data as initial collected data
      save_assessment_state(next_state, form_data)

      # Update analytics
      update_analytics(analytics, message, {
        message: greeting,
        collected_data: form_data
      })

      {
        success: true,
        message: greeting,
        is_complete: false,
        assessment: nil
      }
    end

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

      # Get pre-collected data from form onboarding
      form_data = extract_form_data

      # Merge form data into collected (form data takes precedence as it's already confirmed)
      collected = collected.merge(form_data) { |_key, old, _new| old.presence || _new }

      system_prompt = <<~PROMPT
        당신은 경험 많은 **퍼스널 트레이너**입니다. 새 회원과 첫 상담을 진행합니다.
        마치 헬스장에서 직접 만나 대화하듯 자연스럽고 친근하게 이야기하세요.

        ## 상담 목표
        회원을 **깊이 이해**해서 최적의 맞춤 루틴을 설계하는 것!
        - 일반적인 질문이 아닌, **구체적이고 개인화된 질문**을 하세요
        - 회원의 답변에 **공감하고 반응**하면서 자연스럽게 대화를 이어가세요
        - 트레이너로서 **전문적인 조언**도 중간중간 제공하세요

        ## 🚫 서비스 범위
        이 앱은 **웨이트 트레이닝 전용**입니다 (달리기, 수영 등 미지원)

        ## 📋 이미 파악된 정보
        #{format_form_data(form_data)}
        ⚠️ 위 정보는 다시 묻지 마세요!

        ## 📝 현재까지 수집된 정보
        #{collected.except('conversation_history').to_json}

        🚨 **절대 규칙**:
        - null이 아닌 필드는 **이미 수집 완료**된 것입니다. 절대 다시 묻지 마세요!
        - 사용자가 "없음", "없어요", "따로 없어", "딱히", "특별히" 등으로 답하면 → 해당 정보는 **수집 완료**입니다!
        - 예: preferences: "특별히 없음" → 이미 파악됨, 다시 묻지 마세요!

        ⚠️ **매우 중요**: 사용자가 새로운 정보를 말하면 **반드시** collected_data에 저장하세요!
        - "주 5회, 1시간" → frequency: "주 5회, 1시간"
        - "헬스장" → environment: "헬스장"
        - "어깨 부상" → injuries: "어깨 부상"
        - null인 필드만 업데이트하고, 이미 값이 있는 필드는 유지하세요.

        ## 💬 파악해야 할 항목 (null인 것만!)
        #{format_remaining_questions(collected)}

        ⚠️ **위에 나열된 항목만 질문하세요!** 이미 값이 있는 항목은 질문하지 마세요!
        ⚠️ **program_duration은 반드시 마지막에 물어보세요!** 다른 정보를 모두 파악한 후, 상담 내용을 바탕으로 적절한 프로그램 기간을 추천하면서 물어보세요.
        - 사용자의 경험 수준, 목표, 운동 빈도를 종합 분석하여 최적의 기간을 추천
        - suggestions에도 추천 기간을 포함하되, 사용자가 다른 기간을 선택할 수 있도록 2~3개 옵션 제공

        ## ⏰ 완료 타이밍 (매우 중요!)
        ❌ **절대 먼저 끝내지 마세요!**
        ✅ 사용자가 명시적으로 요청할 때만 완료:
           - "루틴 만들어줘", "이제 시작하자", "충분해", "됐어" 등
        ➡️ 아직 파악 안 된 정보가 있으면 계속 질문하세요
        ➡️ 사용자가 대화를 즐기면 더 깊이 파고들어도 좋아요

        ## 대화 스타일
        - 한 번에 질문 1-2개만 (너무 많으면 부담)
        - 답변에 공감 표현 먼저 → 다음 질문
        - 이모지 적절히 사용 (💪🏋️‍♂️😊 등)
        - 전문 용어는 쉽게 설명
        - 트레이너다운 격려와 조언 포함

        ## 응답 형식 (JSON만 반환 — 절대 규칙!)
        🚨 **반드시 JSON 객체만 반환하세요!** 일반 텍스트로 응답하면 시스템이 깨집니다.
        🚨 **JSON 외 다른 형식은 절대 사용하지 마세요!** 코드블록(```)도 사용하지 마세요.
        **⚠️ collected_data는 이전 값 + 새로 파악한 값을 모두 포함해야 합니다!**
        ```json
        {
          "message": "대화 메시지 (자연스럽게!)",
          "next_state": "conversing",
          "collected_data": {
            "experience": "기존값 유지 또는 새값",
            "frequency": "새로 파악했으면 여기에! (예: 주 5회, 1시간)",
            "goals": "기존값 유지",
            "injuries": "새로 파악했으면 여기에!",
            "preferences": "새로 파악했으면 여기에!",
            "environment": "새로 파악했으면 여기에! (예: 헬스장)",
            "focus_areas": "새로 파악했으면 여기에!",
            "schedule": "새로 파악했으면 여기에!",
            "lifestyle": "새로 파악했으면 여기에!",
            "program_duration": "새로 파악했으면 여기에! (예: 8주, 12주)"
          },
          "suggestions": ["선택지1", "선택지2", "선택지3"],
          "is_complete": false,
          "assessment": null
        }
        ```

        ## 🔘 suggestions 규칙 (매우 중요!)
        - 질문할 때 **반드시** 사용자가 탭할 수 있는 선택지를 suggestions JSON 필드에 포함하세요!
        - 예: "운동 목표가 뭔가요?" → suggestions: ["근육 키우기", "다이어트", "체력 향상", "건강 유지"]
        - 예: "아침형? 저녁형?" → suggestions: ["아침형", "저녁형", "상관없어"]
        - 예: "헬스장 다니세요?" → suggestions: ["헬스장", "홈트레이닝", "둘 다"]
        - 프로그램 기간 질문 시: 상담 내용을 분석해서 적절한 주차를 추천 + "알아서 해줘" 옵션 포함
        - 2~4개가 적당, 사용자가 자유 입력도 가능하므로 대표적인 것만
        - 질문이 아닌 공감/반응만 하는 경우에도 다음 행동 suggestions 제공

        🚨 **suggestions 분리 절대 규칙**:
        - "message" 필드에 suggestions: [...] 텍스트를 **절대** 포함하지 마세요!
        - suggestions는 반드시 별도 JSON 필드("suggestions")에만 넣으세요
        - ❌ 잘못된 예: {"message": "어떤 운동을 좋아하세요?\nsuggestions: [\"A\", \"B\"]", ...}
        - ✅ 올바른 예: {"message": "어떤 운동을 좋아하세요?", "suggestions": ["A", "B"], ...}
        - "message"에는 순수 대화 텍스트만, 선택지 목록(1. 2. 3. 또는 - A\n- B)도 넣지 마세요

        ## 완료 시에만 (사용자가 루틴 요청했을 때)
        ```json
        {
          "message": "상담 마무리 인사",
          "next_state": "completed",
          "collected_data": {...},
          "is_complete": true,
          "assessment": {
            "experience_level": "beginner|intermediate|advanced",
            "numeric_level": null,
            "fitness_goal": "...",
            "summary": "상담 요약"
          }
        }
        ```

        ## 수준 판정 기준
        - beginner: 6개월 미만 / 기본기 부족
        - intermediate: 6개월~2년 / 기본 동작 익힘
        - advanced: 2년+ / 자신만의 루틴 가능
      PROMPT

      messages = []

      # Build initial greeting based on what's already known
      if current_state == STATES[:initial]
        greeting = build_initial_greeting(form_data)
        messages << { role: "assistant", content: greeting }
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

          # Get existing collected data AND form data
          collected = get_collected_data
          form_data = extract_form_data
          history = collected["conversation_history"] || []

          # Get LLM's collected_data but REMOVE conversation_history (we manage it ourselves)
          llm_collected = (data["collected_data"] || {}).except("conversation_history")

          # Merge: form_data < existing collected < LLM response (preserving non-blank values)
          new_collected = form_data.merge(collected.except("conversation_history")) { |_k, old, new_val| old.presence || new_val }
          # Now merge LLM's data, overwriting blank values
          llm_collected.each do |key, value|
            new_collected[key] = value if new_collected[key].blank? && value.present?
          end

          # Trust Claude's response - no code-based fallback parsing needed
          # Claude already analyzed the user message and extracted collected_data in JSON
          Rails.logger.info("[LevelAssessmentService] LLM collected_data: #{llm_collected.inspect}")

          # Check if user explicitly wants to complete and get routine
          is_complete = data["is_complete"] || false
          user_requested_routine = user_wants_routine?(user_message)
          
          # Force complete if user explicitly requested routine
          if user_requested_routine
            is_complete = true
          end

          # ============================================
          # AUTO-COMPLETE: Only if ALL essential info collected
          # Essential = experience + frequency + goals + environment + injuries + schedule + program_duration
          # Ensures thorough consultation before generating routine
          # ============================================
          has_all_essential = new_collected["experience"].present? &&
                              new_collected["frequency"].present? &&
                              new_collected["goals"].present? &&
                              new_collected["environment"].present? &&
                              new_collected["injuries"].present? &&
                              new_collected["schedule"].present? &&
                              new_collected["program_duration"].present?

          if has_all_essential && !is_complete
            Rails.logger.info("[LevelAssessmentService] All essential info collected! Auto-completing.")
            is_complete = true
            data["message"] = build_auto_complete_message(new_collected)
          end
          
          # Build assessment if completing without one
          if is_complete && data["assessment"].blank?
            experience_level = new_collected["experience"] || "intermediate"
            data["assessment"] = {
              "experience_level" => experience_level,
              "fitness_goal" => new_collected["goals"],
              "summary" => build_consultation_summary(new_collected)
            }
            # Only override message if user explicitly requested routine
            if user_requested_routine
              data["message"] = "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪"
            end
          end

          # Add current exchange to history (only non-empty messages)
          new_history = history.dup
          new_history << { "role" => "user", "content" => user_message } if user_message.present?
          new_history << { "role" => "assistant", "content" => data["message"] } if data["message"].present?
          new_collected["conversation_history"] = new_history

          # Ensure assessment always has numeric_level (nil until fitness test)
          assessment = data["assessment"]
          if assessment.is_a?(Hash)
            assessment = assessment.merge("numeric_level" => nil) unless assessment.key?("numeric_level")
          end

          # Extract suggestions from message text BEFORE stripping (if JSON field is empty)
          if Array(data["suggestions"]).empty? && data["message"].present?
            extracted = data["message"].scan(/suggestions\s*:?\s*-?\s*\[([^\]]+)\]/i).flatten.first
            if extracted
              items = extracted.scan(/"([^"]+)"/).flatten
              data["suggestions"] = items.first(4) if items.length >= 2
            end
          end

          # Defensive strip: remove any "suggestions: [...]" text LLM may have embedded in message
          clean_message = strip_suggestions_from_message(data["message"])

          {
            message: clean_message,
            next_state: data["next_state"] || STATES[:asking_experience],
            collected_data: new_collected,
            is_complete: is_complete,
            assessment: assessment,
            suggestions: Array(data["suggestions"]).first(4)
          }
        else
          # Fallback: treat as plain text response (Claude returned text instead of JSON)
          # DO NOT parse user message with code - just preserve existing data
          Rails.logger.warn("[LevelAssessmentService] LLM returned plain text, not JSON. Preserving existing data.")
          collected = get_collected_data
          form_data = extract_form_data
          history = collected["conversation_history"] || []

          # Preserve existing collected data (no code parsing!)
          new_collected = form_data.merge(collected.except("conversation_history"))

          is_complete = user_wants_routine?(user_message)

          # AUTO-COMPLETE: Check if all essential info is collected
          has_all_essential = new_collected["experience"].present? &&
                              new_collected["frequency"].present? &&
                              new_collected["goals"].present? &&
                              new_collected["environment"].present? &&
                              new_collected["injuries"].present? &&
                              new_collected["schedule"].present? &&
                              new_collected["program_duration"].present?

          if has_all_essential && !is_complete
            Rails.logger.info("[LevelAssessmentService] Fallback: All essential info collected! Auto-completing.")
            is_complete = true
          end

          assessment = nil
          final_message = content

          # Extract suggestions from plain text (e.g., 'suggestions: ["A", "B"]')
          fallback_suggestions = []
          suggestions_pattern = /suggestions:\s*-?\s*\[([^\]]+)\]/i
          if final_message =~ suggestions_pattern
            raw = $1
            fallback_suggestions = raw.scan(/"([^"]+)"/).flatten.first(4)
            # Strip suggestions text from message
            final_message = final_message.gsub(/\n*suggestions:\s*-?\s*\[[^\]]*\]\s*/i, "").strip
          end

          if is_complete
            experience_level = new_collected["experience"] || "intermediate"
            assessment = {
              "experience_level" => experience_level,
              "numeric_level" => nil,
              "fitness_goal" => new_collected["goals"],
              "summary" => build_consultation_summary(new_collected)
            }
            final_message = "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪"
          end

          # IMPORTANT: Preserve conversation history!
          new_history = history.dup
          new_history << { "role" => "user", "content" => user_message } if user_message.present?
          new_history << { "role" => "assistant", "content" => final_message } if final_message.present?
          new_collected["conversation_history"] = new_history

          {
            message: final_message,
            next_state: is_complete ? STATES[:completed] : STATES[:asking_experience],
            collected_data: new_collected,
            is_complete: is_complete,
            assessment: assessment,
            suggestions: fallback_suggestions.presence || generate_suggestions_for_plain_text(final_message)
          }
        end
      rescue JSON::ParserError => e
        # DO NOT parse user message with code - just preserve existing data
        Rails.logger.warn("[LevelAssessmentService] JSON parse error: #{e.message}. Preserving existing data.")
        collected = get_collected_data
        form_data = extract_form_data
        history = collected["conversation_history"] || []

        # Preserve existing collected data (no code parsing!)
        new_collected = form_data.merge(collected.except("conversation_history"))

        is_complete = user_wants_routine?(user_message)

        # AUTO-COMPLETE: Check if all essential info is collected
        has_all_essential = new_collected["experience"].present? &&
                            new_collected["frequency"].present? &&
                            new_collected["goals"].present? &&
                            new_collected["environment"].present? &&
                            new_collected["injuries"].present? &&
                            new_collected["schedule"].present? &&
                            new_collected["program_duration"].present?

        if has_all_essential && !is_complete
          Rails.logger.info("[LevelAssessmentService] JSON parse error path: All essential info collected! Auto-completing.")
          is_complete = true
        end

        assessment = nil
        final_message = content

        # Extract suggestions from plain text (e.g., 'suggestions: ["A", "B"]')
        rescue_suggestions = []
        suggestions_pattern = /suggestions:\s*-?\s*\[([^\]]+)\]/i
        if final_message =~ suggestions_pattern
          raw = $1
          rescue_suggestions = raw.scan(/"([^"]+)"/).flatten.first(4)
          final_message = final_message.gsub(/\n*suggestions:\s*-?\s*\[[^\]]*\]\s*/i, "").strip
        end

        if is_complete
          experience_level = new_collected["experience"] || "intermediate"
          assessment = {
            "experience_level" => experience_level,
            "numeric_level" => nil,
            "fitness_goal" => new_collected["goals"],
            "summary" => build_consultation_summary(new_collected)
          }
          final_message = "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪"
        end

        # IMPORTANT: Preserve conversation history!
        new_history = history.dup
        new_history << { "role" => "user", "content" => user_message } if user_message.present?
        new_history << { "role" => "assistant", "content" => final_message } if final_message.present?
        new_collected["conversation_history"] = new_history

        {
          message: final_message,
          next_state: is_complete ? STATES[:completed] : STATES[:asking_experience],
          collected_data: new_collected,
          is_complete: is_complete,
          assessment: assessment,
          suggestions: rescue_suggestions.presence || generate_suggestions_for_plain_text(final_message)
        }
      end
    end

    # Extract data that was already collected during form onboarding
    def extract_form_data
      data = {}

      # Map profile fields to conversation data
      if profile.current_level.present?
        # current_level can be string like "beginner" or numeric_level
        level_str = profile.current_level.to_s.downcase
        data["experience"] = if %w[beginner intermediate advanced].include?(level_str)
                               level_str
                             elsif profile.numeric_level.present?
                               case profile.numeric_level.to_i
                               when 1..2 then "beginner"
                               when 3..5 then "intermediate"
                               else "advanced"
                               end
                             end
      end

      data["goals"] = profile.fitness_goal if profile.fitness_goal.present?

      # Add physical attributes for context
      data["height"] = profile.height if profile.height.present?
      data["weight"] = profile.weight if profile.weight.present?

      data
    end

    # Format form data for display in system prompt
    def format_form_data(form_data)
      return "없음" if form_data.blank?

      lines = []
      lines << "- 운동 경험: #{translate_experience(form_data['experience'])}" if form_data["experience"].present?
      lines << "- 운동 목표: #{form_data['goals']}" if form_data["goals"].present?
      lines << "- 키: #{form_data['height']}cm" if form_data["height"].present?
      lines << "- 몸무게: #{form_data['weight']}kg" if form_data["weight"].present?

      lines.empty? ? "없음" : lines.join("\n")
    end

    def translate_experience(experience)
      case experience
      when "beginner" then "초보 (6개월 미만)"
      when "intermediate" then "중급자 (6개월~2년)"
      when "advanced" then "고급자 (2년 이상)"
      else experience
      end
    end

    # Format remaining questions based on what's still null in collected_data
    def format_remaining_questions(collected)
      questions = {
        "frequency" => "운동 빈도 (주 몇 회, 1회당 시간)",
        "environment" => "운동 환경 (헬스장/홈트/기구)",
        "schedule" => "선호 시간대 (아침/저녁)",
        "injuries" => "부상/통증 여부",
        "focus_areas" => "집중하고 싶은 부위",
        "preferences" => "좋아하는/싫어하는 운동",
        "lifestyle" => "직업/라이프스타일",
        "program_duration" => "희망 프로그램 기간 (몇 주짜리)"
      }

      remaining = questions.select { |key, _| collected[key].blank? }

      if remaining.empty?
        "✅ 모든 기본 정보 파악 완료! 추가로 궁금한 점을 물어보거나, 루틴 생성을 제안하세요."
      else
        remaining.map { |key, desc| "- #{desc}" }.join("\n")
      end
    end

    # Build initial greeting based on what's already known
    def build_initial_greeting(form_data)
      has_experience = form_data["experience"].present?
      has_goals = form_data["goals"].present?

      if has_experience && has_goals
        # Both already known - just ask for frequency
        "안녕하세요! 💪 #{form_data['goals']} 목표로 운동하시는군요! 맞춤 루틴을 만들어드리기 위해 한 가지만 여쭤볼게요. 주 몇 회, 한 번에 몇 시간 정도 운동 가능하세요?"
      elsif has_experience
        # Only experience known
        "안녕하세요! 💪 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 운동 목표가 어떻게 되시나요? (근비대, 다이어트, 체력 향상 등)"
      elsif has_goals
        # Only goals known
        "안녕하세요! 💪 #{form_data['goals']} 목표로 오셨군요! 맞춤 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?"
      else
        # Nothing known - ask about experience first
        "안녕하세요! 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 💪 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?"
      end
    end

    def update_profile_with_assessment(assessment)
      return unless assessment

      # Determine initial level from experience_level (string)
      # This is a starting point - will be refined after fitness test
      experience_level = assessment["experience_level"] || "beginner"
      initial_numeric_level = case experience_level
        when "beginner" then 1
        when "intermediate" then 3
        when "advanced" then 5
        else 1
      end

      # Set both current_level (tier) and numeric_level so routine generation works immediately
      profile.update!(
        fitness_goal: assessment["fitness_goal"],
        current_level: experience_level,  # tier: beginner/intermediate/advanced
        numeric_level: initial_numeric_level,  # numeric: 1-8
        onboarding_completed_at: Time.current,
        fitness_factors: profile.fitness_factors.merge(
          "onboarding_assessment" => assessment,
          "assessment_state" => STATES[:completed],
          "initial_level_source" => "ai_consultation"  # Track that this is from consultation, not fitness test
        )
      )
    end

    # Generate long-term training program after consultation complete
    # Uses RAG + LLM to create personalized multi-week program
    def generate_initial_routine(collected_data)
      Rails.logger.info("[LevelAssessmentService] Generating training program for user #{user.id}")

      # Generate long-term program using ProgramGenerator
      # ProgramGenerator reads collected_data from DB and passes to LLM
      program_result = ProgramGenerator.generate(user: user)

      if program_result[:success] && program_result[:program].present?
        program = program_result[:program]
        Rails.logger.info("[LevelAssessmentService] Training program generated: #{program.id} (#{program.name})")

        {
          success: true,
          program: program,
          coach_message: program_result[:coach_message]
        }
      else
        Rails.logger.warn("[LevelAssessmentService] Failed to generate program: #{program_result[:error]}")
        { success: false, error: program_result[:error] }
      end
    rescue => e
      Rails.logger.error("[LevelAssessmentService] Error generating training program: #{e.message}")
      { success: false, error: e.message }
    end

    def build_completion_message_with_routine(base_message, program_result)
      collected = get_collected_data
      goal = collected["goals"] || profile.fitness_goal || "근력 향상"
      experience = collected["experience"] || "beginner"
      frequency = collected["frequency"] || "주 3회"  # 사용자가 말한 그대로 표시

      # Get program details if available
      program = program_result[:program]
      coach_message = program_result[:coach_message]

      lines = []

      if program.present?
        # Count actual workout days from split_schedule (exclude rest days)
        workout_days = program.split_schedule&.count { |_, info|
          focus = info["focus"] || info[:focus]
          focus.present? && focus != "휴식"
        } || 0

        # Use actual program data
        lines << "🎉 **#{program.name}**을 생성했습니다!"
        lines << ""
        lines << "📋 **프로그램 개요**"
        lines << "• 목표: #{program.goal || goal}"
        lines << "• 총 기간: #{program.total_weeks}주"
        lines << "• 주 #{workout_days > 0 ? workout_days : frequency}회 운동"
        lines << "• 주기화: #{periodization_korean(program.periodization_type)}"
        lines << ""

        # Display weekly plan phases
        if program.weekly_plan.present?
          lines << "📅 **주차별 계획**"
          program.weekly_plan.each do |week_range, info|
            phase = info["phase"] || info[:phase]
            theme = info["theme"] || info[:theme]
            lines << "• #{week_range}주: #{phase} - #{theme}"
          end
          lines << ""
        end

        # Display split schedule summary
        if program.split_schedule.present?
          lines << "🗓️ **운동 분할**"
          split_summary = build_split_summary(program.split_schedule)
          lines << split_summary
          lines << ""
        end

        # Coach message
        if coach_message.present?
          lines << "💬 #{coach_message}"
          lines << ""
        end
      else
        # Fallback to static description
        program_info = build_program_description(goal, experience, days_per_week)

        lines << "🎉 **맞춤 운동 프로그램**을 생성했습니다!"
        lines << ""
        lines << "📋 **프로그램 특징**"
        lines << "• 목표: #{program_info[:goal_korean]}"
        lines << "• 주 #{days_per_week}회 운동 (#{program_info[:split_type]})"
        lines << "• 레벨: #{program_info[:level_korean]} → 점진적 강도 증가"
        lines << ""
      end

      lines << "매일 컨디션과 피드백을 반영해서 **AI가 최적의 루틴을 생성**해드려요! 💪"
      lines << ""
      lines << "---"
      lines << ""
      lines << "오늘의 첫 운동을 시작할까요? 🔥"
      lines << ""
      lines << "1️⃣ 네, 오늘 운동 루틴 보여줘"
      lines << "2️⃣ 프로그램 자세히 설명해줘"
      lines << "3️⃣ 나중에 할게"

      lines.join("\n")
    end

    def periodization_korean(periodization_type)
      case periodization_type.to_s.downcase
      when "linear" then "선형 주기화 (점진적 증가)"
      when "undulating" then "비선형 주기화 (물결형)"
      when "block" then "블록 주기화"
      else "점진적 과부하"
      end
    end

    def build_split_summary(split_schedule)
      day_names = { "1" => "월", "2" => "화", "3" => "수", "4" => "목", "5" => "금", "6" => "토", "7" => "일" }
      summary_parts = []

      split_schedule.each do |day_num, info|
        day_name = day_names[day_num.to_s] || day_num
        focus = info["focus"] || info[:focus]
        next if focus.blank? || focus == "휴식"
        summary_parts << "#{day_name}: #{focus}"
      end

      summary_parts.any? ? summary_parts.join(" / ") : "전신 운동"
    end
    
    def build_program_description(goal, experience, days_per_week)
      goal_korean = case goal.to_s.downcase
        when /근비대|muscle|hypertrophy/ then "근비대 (근육량 증가)"
        when /strength|근력/ then "근력 향상"
        when /다이어트|fat|loss|체중/ then "체지방 감소"
        when /체력|endurance|지구력/ then "체력/지구력 향상"
        else "균형잡힌 체력 향상"
      end
      
      level_korean = case experience.to_s.downcase
        when /beginner|초보/ then "입문자"
        when /intermediate|중급/ then "중급자"
        when /advanced|고급/ then "고급자"
        else "입문자"
      end
      
      split_type = case days_per_week
        when 1..2 then "전신 운동"
        when 3 then "3분할 (상체/하체/전신)"
        when 4 then "상/하체 2분할"
        when 5..6 then "푸시/풀/레그 분할"
        else "전신 운동"
      end
      
      {
        goal_korean: goal_korean,
        level_korean: level_korean,
        split_type: split_type
      }
    end

    def mock_response(user_message = nil)
      state = get_assessment_state
      collected = get_collected_data
      form_data = extract_form_data

      # Merge form data into collected
      collected = form_data.merge(collected)

      # Check if user wants to finish and get routine
      if user_wants_routine?(user_message)
        return complete_assessment(collected)
      end

      # Parse user message based on current state and store it
      if user_message.present?
        case state
        when STATES[:asking_goals]
          collected["goals"] = user_message.strip
        when STATES[:asking_frequency]
          collected["frequency"] = user_message.strip
        when STATES[:asking_experience]
          collected["experience_description"] = user_message.strip
          collected["experience"] ||= "intermediate"
        when "asking_injuries"
          collected["injuries"] = user_message.strip
        when "asking_environment"
          collected["environment"] = user_message.strip
        when "asking_preferences"
          collected["preferences"] = user_message.strip
        when "asking_focus"
          collected["focus_areas"] = user_message.strip
        when "asking_schedule"
          collected["schedule_details"] = user_message.strip
        end
      end

      has_experience = collected["experience"].present?
      has_goals = collected["goals"].present?
      has_frequency = collected["frequency"].present?
      has_injuries = collected["injuries"].present?
      has_environment = collected["environment"].present?
      has_preferences = collected["preferences"].present?
      has_focus = collected["focus_areas"].present?
      has_schedule = collected["schedule_details"].present?

      # Mock conversation flow (API not configured - dev only)
      # No hardcoded suggestions - user types freely
      unless has_goals
        if has_experience
          save_assessment_state(STATES[:asking_goals], collected)
          return { success: true, message: "운동 목표가 어떻게 되시나요?", is_complete: false, assessment: nil, suggestions: [] }
        end
      end

      unless has_frequency
        save_assessment_state(STATES[:asking_frequency], collected)
        return { success: true, message: "주 몇 회 정도 운동하실 수 있으세요?", is_complete: false, assessment: nil, suggestions: [] }
      end

      unless has_schedule
        save_assessment_state("asking_schedule", collected)
        return { success: true, message: "선호하는 운동 시간대가 있으신가요?", is_complete: false, assessment: nil, suggestions: [] }
      end

      unless has_environment
        save_assessment_state("asking_environment", collected)
        return { success: true, message: "운동 환경은 어떻게 되시나요?", is_complete: false, assessment: nil, suggestions: [] }
      end

      unless has_injuries
        save_assessment_state("asking_injuries", collected)
        return { success: true, message: "부상이나 통증이 있는 부위가 있으신가요?", is_complete: false, assessment: nil, suggestions: [] }
      end

      unless has_focus
        save_assessment_state("asking_focus", collected)
        return { success: true, message: "집중하고 싶은 부위가 있으신가요?", is_complete: false, assessment: nil, suggestions: [] }
      end

      unless has_preferences
        save_assessment_state("asking_preferences", collected)
        return { success: true, message: "좋아하거나 피하고 싶은 운동이 있으신가요?", is_complete: false, assessment: nil, suggestions: [] }
      end

      save_assessment_state("ready_to_complete", collected)
      summary = build_consultation_summary(collected)
      {
        success: true,
        message: "#{summary}\n\n맞춤 루틴을 만들어드릴까요?",
        is_complete: false,
        assessment: nil,
        suggestions: []
      }
    end

    def user_wants_routine?(message)
      return false if message.blank?
      message_lower = message.downcase.strip

      # Skip if message is a question (contains ? or ends with interrogative)
      is_question = message_lower.end_with?("?") ||
                    message_lower =~ /(어\?*|나\?*|까\?*|요\?*|죠\?*)$/ ||
                    message_lower.include?("어떻게") ||
                    message_lower.include?("뭐가") ||
                    message_lower.include?("왜")

      # Explicit routine request patterns (high confidence) - match even in questions
      explicit_patterns = [
        "루틴 만들어줘", "루틴 만들어주세요", "루틴 만들어 주세요",
        "루틴 짜줘", "루틴 짜주세요", "루틴 짜 주세요",
        "루틴을 만들어줘", "루틴을 만들어주세요",
        "루틴이요", "루틴 부탁",
        "이제 됐", "이제 충분", "됐어 만들어", "충분해", "그만 물어", "그만 질문"
      ]
      return true if explicit_patterns.any? { |pattern| message_lower.include?(pattern) }

      # Don't match generic keywords if it's a question
      return false if is_question

      # Action request patterns (only non-questions)
      action_patterns = [
        "만들어줘", "만들어주세요", "만들어 주세요", "짜줘", "짜주세요",
        "시작하자", "시작할게", "바로 시작"
      ]
      return true if action_patterns.any? { |pattern| message_lower.include?(pattern) }

      # Single word confirmations (only if message is short)
      if message_lower.length < 10
        short_confirmations = %w[네 응 좋아 그래 오케이 ㅇㅋ ok 알겠어 됐어 충분]
        return true if short_confirmations.any? { |word| message_lower == word }
      end

      false
    end

    def complete_assessment(collected)
      experience_level = collected["experience"] || "intermediate"

      # Calculate initial numeric level from experience
      initial_numeric_level = case experience_level
        when "beginner" then 1
        when "intermediate" then 3
        when "advanced" then 5
        else 1
      end

      update_profile_with_assessment({
        "experience_level" => experience_level,
        "fitness_goal" => collected["goals"],
        "summary" => build_consultation_summary(collected)
      })
      {
        success: true,
        message: "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪",
        is_complete: true,
        assessment: {
          "experience_level" => experience_level,
          "numeric_level" => initial_numeric_level,
          "fitness_goal" => collected["goals"],
          "summary" => build_consultation_summary(collected),
          "consultation_data" => collected
        }
      }
    end


    # When LLM returns plain text instead of JSON, ask LLM to generate suggestions
    # This avoids hardcoding and keeps suggestions contextual
    def generate_suggestions_for_plain_text(message_text)
      return [] if message_text.blank?

      Rails.logger.info("[LevelAssessmentService] Generating suggestions for plain text via LLM")

      response = LlmGateway.chat(
        prompt: message_text,
        task: :level_assessment,
        messages: [
          { role: "user", content: "다음 트레이너의 질문/메시지에 대해 사용자가 탭해서 답할 수 있는 선택지를 2-4개 JSON 배열로만 반환하세요. 다른 텍스트 없이 배열만 출력하세요.\n\n트레이너: #{message_text}" }
        ],
        system: "JSON 배열만 반환하세요. 예: [\"아침형\", \"저녁형\", \"상관없어\"]. 다른 텍스트나 설명 없이 JSON 배열만 출력하세요."
      )

      return [] unless response[:success]

      content = response[:content].strip

      # Try direct JSON array parse
      if content.start_with?("[")
        parsed = JSON.parse(content)
        return Array(parsed).map(&:to_s).first(4) if parsed.is_a?(Array)
      end

      # Try extracting array from content
      if content =~ /\[([^\]]+)\]/
        items = $1.scan(/"([^"]+)"/).flatten
        return items.first(4) if items.length >= 2
      end

      []
    rescue => e
      Rails.logger.warn("[LevelAssessmentService] Failed to generate suggestions for plain text: #{e.message}")
      []
    end

    # Strip "suggestions: [...]" and numbered list text from LLM message
    # Defensive measure: LLM sometimes embeds suggestions in message field
    def strip_suggestions_from_message(msg)
      return msg if msg.blank?

      cleaned = msg.dup
      # Remove "suggestions: [...]" in various formats (unicode spaces, with/without hyphen)
      cleaned.gsub!(/[[:space:]]*suggestions\s*:?\s*-?\s*\[.*?\]/mi, "")
      # Remove trailing numbered lists like "1. option\n2. option\n3. option"
      cleaned.gsub!(/\n+(?:\d+[.)\-]\s*[^\n]+\n*){2,}\z/m, "")
      cleaned.strip
    end

    def build_consultation_summary(collected)
      parts = []
      parts << "#{translate_experience(collected['experience'])}" if collected["experience"]
      parts << "#{collected['goals']} 목표" if collected["goals"]
      parts << "주 #{collected['frequency']} 운동" if collected["frequency"]
      parts << "#{collected['environment']}" if collected["environment"]
      parts << "집중 부위: #{collected['focus_areas']}" if collected["focus_areas"]
      parts << "주의: #{collected['injuries']}" if collected["injuries"] && collected["injuries"] != "없어요"
      parts.join(", ")
    end

    # Build a friendly message when core info is auto-collected
    def build_auto_complete_message(collected)
      experience = translate_experience(collected["experience"])
      goals = collected["goals"]
      frequency = collected["frequency"]
      
      # Build personalized response based on collected info
      msg = "완벽해요! 💪\n\n"
      msg += "**파악된 정보:**\n"
      msg += "- 경험: #{experience}\n"
      msg += "- 목표: #{goals}\n"
      msg += "- 운동 빈도: #{frequency}\n"
      msg += "- 환경: #{collected['environment']}\n" if collected["environment"].present?
      msg += "- 부상: #{collected['injuries']}\n" if collected["injuries"].present? && collected["injuries"] != "없음"
      msg += "- 선호: #{collected['preferences']}\n" if collected["preferences"].present?
      msg += "\n이 정보를 바탕으로 딱 맞는 루틴을 만들어드릴게요! 🏋️"
      
      msg
    end

    # Legacy state handling for backward compatibility
    def mock_response_legacy(user_message, state, collected)
      case state
      when STATES[:initial]
        save_assessment_state(STATES[:asking_experience], collected)
        {
          success: true,
          message: "안녕하세요! 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 💪 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?",
          is_complete: false,
          assessment: nil
        }
      when STATES[:asking_experience]
        collected["experience"] ||= "intermediate"
        save_assessment_state(STATES[:asking_frequency], collected)
        {
          success: true,
          message: "좋아요! 경험이 있으시네요. 💪 주 몇 회 정도 운동하시나요?",
          is_complete: false,
          assessment: nil
        }
      when STATES[:asking_frequency]
        collected["frequency"] ||= "3회"
        save_assessment_state(STATES[:asking_goals], collected)
        {
          success: true,
          message: "주 3회 정도면 좋은 루틴을 짤 수 있어요! 운동 목표가 뭔가요? (근비대, 다이어트, 체력 향상 등)",
          is_complete: false,
          assessment: nil
        }
      when STATES[:asking_goals]
        collected["goals"] ||= "근비대"
        complete_assessment(collected)
      else
        # Unknown state - complete with what we have
        {
          success: true,
          message: "좋아요! 대략적인 상황 파악됐어요. 💪",
          is_complete: true,
          assessment: {
            "experience_level" => collected["experience"] || "intermediate",
            "numeric_level" => nil,
            "fitness_goal" => collected["goals"],
            "summary" => "#{translate_experience(collected['experience'] || 'intermediate')}, 주 #{collected['frequency']} 운동 가능, #{collected['goals']} 목표"
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
