#!/usr/bin/env ruby
# frozen_string_literal: true

# Onboarding Conversation Simulation Script
# Tests various user personas to validate AI trainer behavior

require 'net/http'
require 'json'
require 'uri'

API_URL = ENV['API_URL'] || 'https://repstack-backend-production.up.railway.app/graphql'

# User personas with different characteristics
PERSONAS = [
  # === 초보자 그룹 ===
  {
    name: "완전 초보자",
    messages: ["처음이에요", "주 3회 정도요", "살 빼고 싶어요"]
  },
  {
    name: "초보자 - 질문형",
    messages: ["운동 처음인데요", "주 몇 번이 좋을까요?", "다이어트가 목표예요"]
  },
  {
    name: "초보자 - 상세 답변",
    messages: ["운동은 처음이에요. 학교 체육시간 외에는 해본 적이 없어요", "주 3-4회 정도 시간이 나요. 퇴근 후에 1시간 정도요", "체중 감량이 목표예요. 10kg 정도 빼고 싶어요"]
  },
  {
    name: "초보자 - 부상 이력",
    messages: ["처음이에요", "주 4회요", "근육 키우고 싶은데, 허리가 좀 안 좋아요"]
  },
  {
    name: "초보자 - 시간 제약",
    messages: ["운동 경험 없어요", "주 2회밖에 시간이 안 나요", "체력 향상이 목표예요"]
  },

  # === 중급자 그룹 ===
  {
    name: "중급자 - 일반",
    messages: ["1년 정도 했어요", "주 4회 운동해요", "근비대가 목표예요"]
  },
  {
    name: "중급자 - 질문형",
    messages: ["6개월 정도 해봤어요", "주 3회인데 늘려야 할까요?", "벌크업 하고 싶은데 어떻게 해야 할까요?"]
  },
  {
    name: "중급자 - 구체적 목표",
    messages: ["1년 반 정도 했습니다", "주 5회 가능해요", "벤치프레스 100kg 치고 싶어요"]
  },
  {
    name: "중급자 - 복귀자",
    messages: ["예전에 2년 했다가 1년 쉬었어요", "다시 주 3회로 시작하려고요", "예전 몸으로 돌아가고 싶어요"]
  },
  {
    name: "중급자 - 부상 경험",
    messages: ["1년 정도 했어요", "주 4회요", "어깨 부상이 있어서 조심해야 해요"]
  },

  # === 고급자 그룹 ===
  {
    name: "고급자 - 일반",
    messages: ["5년 넘게 했어요", "주 6회 운동해요", "대회 준비 중이에요"]
  },
  {
    name: "고급자 - 세부 목표",
    messages: ["3년 정도 꾸준히 했습니다", "주 5회요", "상체 볼륨을 더 키우고 싶어요"]
  },

  # === 특수 케이스 ===
  {
    name: "짧은 답변만",
    messages: ["처음", "주3", "다이어트"]
  },
  {
    name: "애매한 답변",
    messages: ["잘 모르겠어요", "시간 날 때마다요", "그냥 건강해지고 싶어요"]
  },
  {
    name: "많은 질문",
    messages: ["초보인데요, 웨이트가 좋을까요 유산소가 좋을까요?", "주 몇 번이 적당할까요? 매일 해도 될까요?", "단백질은 얼마나 먹어야 하나요?"]
  },
  {
    name: "목표 변경",
    messages: ["6개월 정도요", "주 4회요", "처음엔 다이어트였는데 이제 근육도 키우고 싶어요"]
  },
  {
    name: "홈트레이닝",
    messages: ["처음이에요", "주 5회 집에서 할 수 있어요", "홈트로 몸 만들고 싶어요"]
  },
  {
    name: "바쁜 직장인",
    messages: ["처음이에요", "점심시간 30분밖에 안 되는데 가능할까요?", "체중 관리가 목표예요"]
  },
  {
    name: "나이 언급",
    messages: ["운동은 처음이에요. 40대인데 늦은 건 아닐까요?", "주 3회 정도요", "건강 관리가 목표예요"]
  },
  {
    name: "다이어트 집착",
    messages: ["처음이에요", "매일 할 수 있어요", "빨리 살 빼고 싶어요. 한 달에 10kg 가능할까요?"]
  },
]

class OnboardingSimulator
  def initialize
    @results = []
    @total_turns = 0
    @completed_count = 0
    @failed_count = 0
  end

  def run(count = 20)
    puts "=" * 60
    puts "🏋️ 온보딩 대화 시뮬레이션 시작"
    puts "=" * 60
    puts ""

    personas_to_test = count > PERSONAS.length ?
      (PERSONAS * (count / PERSONAS.length + 1)).take(count) :
      PERSONAS.take(count)

    personas_to_test.each_with_index do |persona, idx|
      puts "\n#{'-' * 50}"
      puts "👤 [#{idx + 1}/#{count}] #{persona[:name]}"
      puts '-' * 50

      result = simulate_persona(persona)
      @results << result

      if result[:completed]
        @completed_count += 1
        @total_turns += result[:turns]
        puts "✅ 완료 (#{result[:turns]}턴)"
      else
        @failed_count += 1
        puts "❌ 실패: #{result[:error]}"
      end
    end

    print_summary
  end

  private

  def simulate_persona(persona)
    # Create fresh user
    token = create_user(persona[:name])
    return { completed: false, error: "Failed to create user" } unless token

    turns = 0
    max_turns = 10
    conversation = []

    # Initial greeting - send empty or hello message to start
    response = send_chat(token, "안녕하세요")
    turns += 1

    if response.nil?
      return { completed: false, error: "API error on initial message" }
    end

    conversation << { role: "assistant", content: response[:message] }
    puts "  🤖 #{truncate(response[:message], 60)}"

    # Continue with persona messages
    persona[:messages].each do |user_message|
      break if response[:is_complete]

      puts "  👤 #{user_message}"
      conversation << { role: "user", content: user_message }

      response = send_chat(token, user_message)
      turns += 1

      if response.nil?
        return { completed: false, error: "API error", turns: turns, conversation: conversation }
      end

      conversation << { role: "assistant", content: response[:message] }
      puts "  🤖 #{truncate(response[:message], 60)}"

      if response[:is_complete]
        puts "  🎯 isComplete: true 수신!"
        return {
          completed: true,
          turns: turns,
          conversation: conversation,
          assessment: response[:assessment]
        }
      end
    end

    # If not complete, continue with follow-up
    follow_ups = ["네 알겠어요", "그렇군요", "좋아요", "시작할게요"]
    follow_ups.each do |msg|
      break if turns >= max_turns

      puts "  👤 #{msg}"
      response = send_chat(token, msg)
      turns += 1

      if response.nil?
        return { completed: false, error: "API error", turns: turns }
      end

      puts "  🤖 #{truncate(response[:message], 60)}"

      if response[:is_complete]
        puts "  🎯 isComplete: true 수신!"
        return { completed: true, turns: turns, conversation: conversation }
      end
    end

    { completed: false, error: "Max turns reached", turns: turns, conversation: conversation }
  end

  def create_user(name)
    query = <<~GQL
      mutation {
        devSignInFresh(input: { name: "#{name.gsub('"', '\\"')}" }) {
          authPayload {
            token
          }
          errors
        }
      }
    GQL

    response = graphql_request(query)
    return nil unless response

    data = response.dig("data", "devSignInFresh")
    return nil if data.nil? || data["errors"]&.any?

    data.dig("authPayload", "token")
  rescue => e
    puts "  ⚠️ User creation error: #{e.message}"
    nil
  end

  def send_chat(token, message)
    query = <<~GQL
      mutation {
        chat(input: { message: "#{message.gsub('"', '\\"')}" }) {
          success
          message
          intent
          data {
            isComplete
            assessment {
              experienceLevel
              fitnessGoal
            }
          }
          error
        }
      }
    GQL

    response = graphql_request(query, token)
    return nil unless response

    if response["errors"]
      puts "  ⚠️ GraphQL error: #{response['errors'].first['message']}"
      return nil
    end

    data = response.dig("data", "chat")
    return nil unless data && data["success"]

    chat_data = data["data"] || {}

    {
      message: data["message"],
      intent: data["intent"],
      is_complete: chat_data["isComplete"] == true,
      assessment: chat_data["assessment"]
    }
  rescue => e
    puts "  ⚠️ Chat error: #{e.message}"
    nil
  end

  def graphql_request(query, token = nil)
    headers = ["-H 'Content-Type: application/json'"]
    headers << "-H 'Authorization: Bearer #{token}'" if token

    body = { query: query }.to_json.gsub("'", "'\\''")

    cmd = "curl -s -X POST #{headers.join(' ')} -d '#{body}' '#{API_URL}'"
    response = `#{cmd}`

    JSON.parse(response)
  rescue => e
    puts "  ⚠️ Request error: #{e.message}"
    nil
  end

  def truncate(str, length)
    return str if str.nil? || str.length <= length
    str[0...length] + "..."
  end

  def print_summary
    puts "\n"
    puts "=" * 60
    puts "📊 시뮬레이션 결과 요약"
    puts "=" * 60
    puts ""
    puts "총 테스트: #{@results.length}"
    puts "성공: #{@completed_count} (#{(@completed_count.to_f / @results.length * 100).round(1)}%)"
    puts "실패: #{@failed_count}"
    puts ""

    if @completed_count > 0
      avg_turns = (@total_turns.to_f / @completed_count).round(1)
      puts "평균 대화 턴 수: #{avg_turns}"
    end

    # Failure analysis
    if @failed_count > 0
      puts "\n❌ 실패 케이스:"
      @results.select { |r| !r[:completed] }.each do |r|
        # Find persona name from results
      end
    end

    puts ""
    puts "=" * 60
  end
end

# Run simulation
if __FILE__ == $0
  count = ARGV[0]&.to_i || 20
  simulator = OnboardingSimulator.new
  simulator.run(count)
end
