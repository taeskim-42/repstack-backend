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

    # Handle initial greeting using form_data directly (no LLM call needed)
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

        ## 응답 형식 (JSON만 반환)
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
            "lifestyle": "새로 파악했으면 여기에!"
          },
          "is_complete": false,
          "assessment": null
        }
        ```

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
          # Now merge LLM's data, only if our existing value is blank
          llm_collected.each do |key, value|
            new_collected[key] = value if new_collected[key].blank? && value.present?
          end

          # Aggressive fallback: extract key info from user message ALWAYS (not just when LLM missed it)
          # This ensures user answers are captured even if LLM doesn't parse them correctly
          new_collected = extract_info_from_message(user_message, new_collected, history)

          # Check if user explicitly wants to complete and get routine
          is_complete = data["is_complete"] || false
          user_requested_routine = user_wants_routine?(user_message)
          
          # Force complete if user explicitly requested routine
          if user_requested_routine
            is_complete = true
          end

          # ============================================
          # AUTO-COMPLETE: If core info collected, complete immediately
          # Core info = experience + frequency + goals
          # ============================================
          has_core_info = new_collected["experience"].present? && 
                          new_collected["frequency"].present? && 
                          new_collected["goals"].present?
          
          if has_core_info && !is_complete
            Rails.logger.info("[LevelAssessmentService] Core info collected! Auto-completing. experience=#{new_collected['experience']}, frequency=#{new_collected['frequency']}, goals=#{new_collected['goals']}")
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
            # Only override message if user explicitly requested
            if user_requested_routine && !has_core_info
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

          {
            message: data["message"],
            next_state: data["next_state"] || STATES[:asking_experience],
            collected_data: new_collected,
            is_complete: is_complete,
            assessment: assessment
          }
        else
          # Fallback: treat as plain text response
          collected = get_collected_data
          form_data = extract_form_data
          new_collected = form_data.merge(collected.except("conversation_history"))
          new_collected = extract_info_from_message(user_message, new_collected, collected["conversation_history"] || [])
          
          is_complete = user_wants_routine?(user_message)
          assessment = nil
          final_message = content
          
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
          
          {
            message: final_message,
            next_state: is_complete ? STATES[:completed] : STATES[:asking_experience],
            collected_data: new_collected,
            is_complete: is_complete,
            assessment: assessment
          }
        end
      rescue JSON::ParserError
        collected = get_collected_data
        form_data = extract_form_data
        new_collected = form_data.merge(collected.except("conversation_history"))
        new_collected = extract_info_from_message(user_message, new_collected, collected["conversation_history"] || [])
        
        is_complete = user_wants_routine?(user_message)
        assessment = nil
        final_message = content
        
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
        
        {
          message: final_message,
          next_state: is_complete ? STATES[:completed] : STATES[:asking_experience],
          collected_data: new_collected,
          is_complete: is_complete,
          assessment: assessment
        }
      end
    end

    # Extract information from user message - aggressive fallback parsing
    def extract_info_from_message(user_message, collected, history)
      return collected if user_message.blank?

      msg = user_message.downcase
      new_collected = collected.dup

      # Get last assistant message to understand context
      last_assistant_msg = (history.select { |h| h["role"] == "assistant" }.last || {})["content"].to_s.downcase

      # Check if user said "없음" or similar - route to correct field based on context
      none_keywords = %w[없음 없어 없어요 없습니다 딱히 따로 특별히 상관없 아무거나]
      is_none_answer = none_keywords.any? { |kw| msg.include?(kw) } && msg.length < 20

      if is_none_answer
        # Determine which question was being asked based on last assistant message
        if last_assistant_msg.include?("집중") || last_assistant_msg.include?("부위") || last_assistant_msg.include?("키우고") || last_assistant_msg.include?("발달")
          new_collected["focus_areas"] ||= "전체 균형"
        elsif last_assistant_msg.include?("부상") || last_assistant_msg.include?("통증") || last_assistant_msg.include?("아픈")
          new_collected["injuries"] ||= "없음"
        elsif last_assistant_msg.include?("좋아하") || last_assistant_msg.include?("싫어") || last_assistant_msg.include?("선호") || last_assistant_msg.include?("피하")
          new_collected["preferences"] ||= "특별히 없음"
        elsif last_assistant_msg.include?("환경") || last_assistant_msg.include?("헬스장") || last_assistant_msg.include?("홈트") || last_assistant_msg.include?("어디서")
          new_collected["environment"] ||= "특별히 없음"
        end
      else
        # ============================================
        # PRIORITY 1: Extract experience level (years)
        # Always try to extract, overwrite if we find a match
        # ============================================
        # Match patterns like "2년", "2년 넘게", "3년째", "6개월", "해온지 2년"
        year_match = user_message.match(/(\d+)\s*년/)
        month_match = user_message.match(/(\d+)\s*개월/)
        
        if year_match
          years = year_match[1].to_i
          new_collected["experience_years"] = "#{years}년 이상"
          # Auto-determine experience level
          if years >= 2
            new_collected["experience"] = "advanced"
          elsif years >= 1
            new_collected["experience"] = "intermediate"
          else
            new_collected["experience"] = "beginner"
          end
          Rails.logger.info("[LevelAssessmentService] Extracted experience: #{years}년 -> #{new_collected['experience']}")
        elsif month_match
          months = month_match[1].to_i
          new_collected["experience_years"] = "#{months}개월"
          if months >= 6
            new_collected["experience"] = "intermediate"
          else
            new_collected["experience"] = "beginner"
          end
          Rails.logger.info("[LevelAssessmentService] Extracted experience: #{months}개월 -> #{new_collected['experience']}")
        end

        # ============================================
        # PRIORITY 2: Extract frequency (days per week + duration)
        # Always try to extract if we find a pattern
        # ============================================
        freq_match = user_message.match(/주\s*(\d+)\s*회|(\d+)\s*회/)
        # More flexible time patterns: "1시간 반", "1시간", "90분", "30분"
        time_match = user_message.match(/(\d+)\s*시간\s*(반)?|(\d+)\s*분/)
        
        freq_parts = []
        if freq_match
          freq_parts << "주 #{freq_match[1] || freq_match[2]}회"
        end
        if time_match
          if time_match[1] # hours
            hours = time_match[1]
            if time_match[2] # "반" (half)
              freq_parts << "#{hours}시간 30분"
            else
              freq_parts << "#{hours}시간"
            end
          elsif time_match[3] # minutes only
            freq_parts << "#{time_match[3]}분"
          end
        end
        
        if freq_parts.any?
          new_collected["frequency"] = freq_parts.join(", ")
          Rails.logger.info("[LevelAssessmentService] Extracted frequency: #{new_collected['frequency']}")
        end

        # ============================================
        # PRIORITY 3: Extract goals
        # Always try to extract if we find a keyword
        # ============================================
        goal_keywords = {
          "근비대" => ["근비대", "근육 키우", "벌크", "bulk", "머슬", "muscle", "사이즈"],
          "다이어트" => ["다이어트", "살빼", "체중감량", "fat", "컷팅", "cut", "체지방"],
          "체력" => ["체력", "지구력", "스태미나", "stamina"],
          "건강" => ["건강", "유지", "health"],
          "strength" => ["근력", "힘", "strength", "스트렝스", "파워", "강해"]
        }
        
        goal_keywords.each do |goal, keywords|
          if keywords.any? { |kw| msg.include?(kw) }
            new_collected["goals"] = goal
            Rails.logger.info("[LevelAssessmentService] Extracted goal: #{goal}")
            break
          end
        end

        # ============================================
        # Extract environment
        # ============================================
        if new_collected["environment"].blank?
          if msg.include?("헬스장") || msg.include?("gym") || msg.include?("짐") || msg.include?("피트니스") || msg.include?("풀 장비")
            new_collected["environment"] = "헬스장 (풀 장비)"
          elsif msg.include?("홈트") || msg.include?("집에서") || msg.include?("home") || msg.include?("집이")
            new_collected["environment"] = "홈트레이닝"
          elsif last_assistant_msg.include?("환경") || last_assistant_msg.include?("헬스장") || last_assistant_msg.include?("홈트") || last_assistant_msg.include?("어디서")
            if msg.length < 50 && !is_none_answer
              new_collected["environment"] = user_message.strip
            end
          end
        end

        # ============================================
        # Extract injuries/pain
        # ============================================
        if new_collected["injuries"].blank?
          no_injury_patterns = ["부상은 없", "부상 없", "다친 곳 없", "통증 없", "아픈 곳 없", "괜찮아", "부상 없고", "없고"]
          if no_injury_patterns.any? { |p| msg.include?(p) }
            new_collected["injuries"] = "없음"
          elsif last_assistant_msg.include?("부상") || last_assistant_msg.include?("통증") || last_assistant_msg.include?("아픈")
            injury_keywords = %w[부상 파열 통증 아픔 인대 디스크 허리 무릎 어깨 손목 팔꿈치]
            if injury_keywords.any? { |kw| msg.include?(kw) }
              new_collected["injuries"] = user_message.strip
            elsif msg.length < 30
              new_collected["injuries"] = user_message.strip
            end
          end
        end

        # ============================================
        # Extract preferences (likes/dislikes)
        # ============================================
        if new_collected["preferences"].blank?
          # Check for specific exercise mentions with "좋아해" or similar
          exercise_names = %w[풀업 턱걸이 벤치 스쿼트 데드 데드리프트 로우 프레스 컬 레이즈 런지 플랭크]
          liked = exercise_names.select { |ex| msg.include?(ex) && (msg.include?("좋아") || msg.include?("선호")) }
          disliked = exercise_names.select { |ex| msg.include?(ex) && (msg.include?("싫어") || msg.include?("피") || msg.include?("안")) }
          
          if liked.any? || disliked.any?
            pref_parts = []
            pref_parts << "선호: #{liked.join(', ')}" if liked.any?
            pref_parts << "비선호: #{disliked.join(', ')}" if disliked.any?
            new_collected["preferences"] = pref_parts.join(" / ")
          elsif msg.include?("좋아") && exercise_names.any? { |ex| msg.include?(ex) }
            # Just mentioned liking something
            new_collected["preferences"] = user_message.strip
          end
        end

        # ============================================
        # Extract schedule/time preference
        # ============================================
        if new_collected["schedule"].blank?
          if msg.include?("아침") || msg.include?("새벽") || msg.include?("오전")
            new_collected["schedule"] = "아침"
          elsif msg.include?("저녁") || msg.include?("퇴근") || msg.include?("밤")
            new_collected["schedule"] = "저녁"
          elsif msg.include?("점심") || msg.include?("낮")
            new_collected["schedule"] = "점심"
          elsif last_assistant_msg.include?("시간") || last_assistant_msg.include?("언제") || last_assistant_msg.include?("요일")
            if msg.length < 50
              new_collected["schedule"] = user_message.strip
            end
          end
        end

        # ============================================
        # Extract focus areas (body parts)
        # ============================================
        if new_collected["focus_areas"].blank?
          body_parts = %w[어깨 가슴 등 팔 하체 다리 복근 코어 전신 상체 삼두 이두 엉덩이 힙 광배]
          matched = body_parts.select { |part| msg.include?(part) }
          if matched.any?
            new_collected["focus_areas"] = matched.join(", ")
          elsif last_assistant_msg.include?("부위") || last_assistant_msg.include?("집중") || last_assistant_msg.include?("키우") || last_assistant_msg.include?("발달")
            if msg.length < 50
              new_collected["focus_areas"] = user_message.strip
            end
          end
        end

        # ============================================
        # Extract lifestyle info
        # ============================================
        if new_collected["lifestyle"].blank?
          if msg.include?("앉아") || msg.include?("사무") || msg.include?("데스크") || msg.include?("컴퓨터") || msg.include?("회사")
            new_collected["lifestyle"] = "사무직/앉아있는 시간 많음"
          elsif msg.include?("서서") || msg.include?("활동적") || msg.include?("움직") || msg.include?("육체")
            new_collected["lifestyle"] = "활동적인 직업"
          elsif msg.include?("학생")
            new_collected["lifestyle"] = "학생"
          end
        end
      end

      # Log what was extracted for debugging
      Rails.logger.info("[LevelAssessmentService] Extracted from message '#{user_message}': experience=#{new_collected['experience']}, frequency=#{new_collected['frequency']}, goals=#{new_collected['goals']}, environment=#{new_collected['environment']}, injuries=#{new_collected['injuries']}, preferences=#{new_collected['preferences']}")

      new_collected
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
        "lifestyle" => "직업/라이프스타일"
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

      # Conversation flow - ask questions in order, like a real trainer consultation
      # 1. Goals (from form or ask)
      unless has_goals
        if has_experience
          save_assessment_state(STATES[:asking_goals], collected)
          return {
            success: true,
            message: "좋아요! 운동 목표가 어떻게 되시나요? 근육 키우기, 다이어트, 체력 향상, 건강 유지 등 편하게 말씀해주세요 😊",
            is_complete: false,
            assessment: nil
          }
        end
      end

      # 2. Frequency (must ask)
      unless has_frequency
        save_assessment_state(STATES[:asking_frequency], collected)
        goal_comment = collected["goals"] ? "#{collected['goals']} 목표시네요! " : ""
        return {
          success: true,
          message: "#{goal_comment}주 몇 회 정도 운동하실 수 있으세요? 한 번에 얼마나 시간을 쓸 수 있는지도 알려주시면 좋아요!",
          is_complete: false,
          assessment: nil
        }
      end

      # 3. Schedule details (when they can workout)
      unless has_schedule
        save_assessment_state("asking_schedule", collected)
        return {
          success: true,
          message: "혹시 특정 요일이나 시간대에 운동하시나요? (예: 평일 저녁, 주말 오전 등) 아니면 유동적인가요?",
          is_complete: false,
          assessment: nil
        }
      end

      # 4. Environment
      unless has_environment
        save_assessment_state("asking_environment", collected)
        return {
          success: true,
          message: "운동 환경은 어떻게 되시나요? 헬스장을 다니시나요, 아니면 홈트레이닝 위주인가요? 사용 가능한 기구가 있다면 알려주세요!",
          is_complete: false,
          assessment: nil
        }
      end

      # 5. Injuries/limitations
      unless has_injuries
        save_assessment_state("asking_injuries", collected)
        return {
          success: true,
          message: "혹시 부상이나 통증이 있는 부위가 있으신가요? 아니면 피해야 할 동작이 있나요? 없으시면 '없어요'라고 해주세요 😊",
          is_complete: false,
          assessment: nil
        }
      end

      # 6. Focus areas
      unless has_focus
        save_assessment_state("asking_focus", collected)
        return {
          success: true,
          message: "특별히 발달시키고 싶은 부위가 있으신가요? (예: 어깨, 가슴, 등, 하체 등) 전체적으로 균형 있게 하고 싶으시면 그렇게 말씀해주셔도 돼요!",
          is_complete: false,
          assessment: nil
        }
      end

      # 7. Preferences
      unless has_preferences
        save_assessment_state("asking_preferences", collected)
        return {
          success: true,
          message: "좋아하는 운동이나 피하고 싶은 운동이 있으신가요? 예를 들어 '스쿼트는 좋아하는데 데드리프트는 무서워요' 같은 거요 😄",
          is_complete: false,
          assessment: nil
        }
      end

      # All info collected - prompt user to confirm or ask more
      save_assessment_state("ready_to_complete", collected)
      summary = build_consultation_summary(collected)
      {
        success: true,
        message: "#{summary}\n\n이 정보를 바탕으로 맞춤 루틴을 만들어드릴까요? 더 얘기하고 싶은 게 있으시면 편하게 말씀해주세요! 🏋️",
        is_complete: false,
        assessment: nil
      }
    end

    def user_wants_routine?(message)
      return false if message.blank?
      message_lower = message.downcase.strip

      # Explicit routine request patterns (high confidence)
      explicit_patterns = [
        "루틴 만들어", "루틴 짜", "루틴을 만들어", "루틴이요", "루틴 부탁",
        "만들어줘", "만들어주세요", "만들어 주세요", "짜줘", "짜주세요",
        "시작하자", "시작할게", "시작해", "바로 시작",
        "이제 됐", "이제 충분", "됐어", "충분해", "그만 물어", "그만 질문"
      ]
      return true if explicit_patterns.any? { |pattern| message_lower.include?(pattern) }

      # Single word confirmations (only if message is short)
      if message_lower.length < 15
        short_confirmations = %w[네 응 좋아 그래 오케이 ㅇㅋ ok 알겠어 고마워 됐어 충분 시작]
        return true if short_confirmations.any? { |word| message_lower == word || message_lower.start_with?(word) }
      end

      # Check for routine-related keywords in longer messages
      routine_keywords = %w[루틴 만들어 짜줘 시작]
      routine_keywords.any? { |keyword| message_lower.include?(keyword) }
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
