# frozen_string_literal: true

module AiTrainer
  module LevelAssessment
    # Builds prompts, greetings, and conversation structures for level assessment.
    # All methods access instance variables (@user, @profile) from the host class.
    module PromptBuilder
      include AssessmentConstants

      # Build conversation messages + system prompt for the LLM
      def build_conversation(user_message, current_state)
        collected = get_collected_data
        form_data = extract_form_data

        # Merge: form_data fills in blanks from collected (already-confirmed data wins)
        collected = collected.merge(form_data) { |_key, old, _new| old.presence || _new }

        system_prompt = build_system_prompt(form_data, collected)
        messages = build_message_history(collected, current_state, form_data, user_message)

        { system: system_prompt, messages: messages }
      end

      # Fallback greeting when LLM is unavailable
      def build_personalized_greeting(form_data)
        name = user.name || "회원"
        goal = form_data["goals"] || profile.fitness_goal
        experience = form_data["experience"]

        lines = [ "#{name}님, 안녕하세요! 💪" ]

        known_info = build_known_info_lines(form_data, goal, experience)
        if known_info.any?
          lines << ""
          lines << "입력해주신 정보를 확인했어요:"
          lines.concat(known_info.map { |info| "- #{info}" })
        end

        lines << ""
        lines << "더 정확한 맞춤 루틴을 위해 몇 가지만 더 여쭤볼게요! 😊"

        missing = determine_missing_questions(form_data)
        if missing.any?
          lines << ""
          lines << missing.first
        end

        lines.join("\n")
      end

      # Build initial (legacy) greeting based on form data
      def build_initial_greeting(form_data)
        has_experience = form_data["experience"].present?
        has_goals = form_data["goals"].present?

        if has_experience && has_goals
          "안녕하세요! 💪 #{form_data['goals']} 목표로 운동하시는군요! 맞춤 루틴을 만들어드리기 위해 한 가지만 여쭤볼게요. 주 몇 회, 한 번에 몇 시간 정도 운동 가능하세요?"
        elsif has_experience
          "안녕하세요! 💪 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 운동 목표가 어떻게 되시나요? (근비대, 다이어트, 체력 향상 등)"
        elsif has_goals
          "안녕하세요! 💪 #{form_data['goals']} 목표로 오셨군요! 맞춤 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?"
        else
          "안녕하세요! 맞춤 웨이트 트레이닝 루틴을 만들어드리기 위해 몇 가지 여쭤볼게요. 💪 헬스장이나 웨이트 운동 경험이 어느 정도 되시나요?"
        end
      end

      # Determine which questions are still unanswered
      def determine_missing_questions(form_data)
        questions = []
        questions << "우선, **주에 몇 번, 한 번에 몇 시간** 정도 운동하실 수 있으세요?" if form_data["frequency"].blank?
        questions << "운동 환경은 어떻게 되세요? (헬스장/홈트/기구 유무)" if form_data["environment"].blank?
        questions << "혹시 부상이나 피해야 할 동작이 있으신가요?" if form_data["injuries"].blank?
        questions
      end

      # Determine which state to move to based on what's already known
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

      # Format remaining (unanswered) question categories for the system prompt
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
        return "✅ 모든 기본 정보 파악 완료! 추가로 궁금한 점을 물어보거나, 루틴 생성을 제안하세요." if remaining.empty?

        remaining.map { |_key, desc| "- #{desc}" }.join("\n")
      end

      def translate_experience(experience)
        case experience
        when "beginner" then "초보 (6개월 미만)"
        when "intermediate" then "중급자 (6개월~2년)"
        when "advanced" then "고급자 (2년 이상)"
        else experience
        end
      end

      private

      def build_known_info_lines(form_data, goal, experience)
        known_info = []
        known_info << "**#{goal}** 목표" if goal.present?
        known_info << "**#{translate_experience(experience)}** 수준" if experience.present?
        known_info << "키 **#{form_data['height']}cm**" if form_data["height"].present?
        known_info << "체중 **#{form_data['weight']}kg**" if form_data["weight"].present?
        known_info
      end

      def build_system_prompt(form_data, collected)
        <<~PROMPT
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
      end

      def build_message_history(collected, current_state, form_data, user_message)
        messages = []

        if current_state == STATES[:initial]
          greeting = build_initial_greeting(form_data)
          messages << { role: "assistant", content: greeting }
        end

        if collected["conversation_history"].present?
          collected["conversation_history"].each do |turn|
            next if turn["content"].blank?
            messages << { role: turn["role"], content: turn["content"] }
          end
        end

        messages << { role: "user", content: user_message }
        messages
      end
    end
  end
end
