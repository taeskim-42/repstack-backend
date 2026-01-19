# frozen_string_literal: true

# AI Trainer Service - handles AI-powered fitness assessments and recommendations
class AiTrainerService
  API_URL = "https://api.anthropic.com/v1/messages"
  MODEL = "claude-sonnet-4-20250514"
  MAX_TOKENS = 2048

  class << self
    def level_test(input)
      new.level_test(input)
    end

    def check_condition(input)
      new.check_condition(input)
    end

    def analyze_feedback(input)
      new.analyze_feedback(input)
    end

    def generate_routine(user:, day_of_week: nil, condition_inputs: {})
      new.generate_routine(user: user, day_of_week: day_of_week, condition_inputs: condition_inputs)
    end

    def generate_level_test(user:)
      new.generate_level_test_for_user(user)
    end

    def evaluate_level_test(user:, test_results:)
      new.evaluate_level_test_results(user: user, test_results: test_results)
    end

    def check_test_eligibility(user:)
      new.check_eligibility(user)
    end
  end

  def level_test(input)
    return mock_level_test_result(input) unless api_configured?

    prompt = build_level_test_prompt(input)
    result = call_claude_api(prompt, "level_test")

    if result[:success]
      parse_level_test_response(result[:data])
    else
      { success: false, error: result[:error] }
    end
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.level_test error: #{e.message}")
    { success: false, error: "Level test failed: #{e.message}" }
  end

  def check_condition(input)
    return mock_condition_result(input) unless api_configured?

    prompt = build_condition_prompt(input)
    result = call_claude_api(prompt, "check_condition")

    if result[:success]
      parse_condition_response(result[:data])
    else
      { success: false, error: result[:error] }
    end
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.check_condition error: #{e.message}")
    { success: false, error: "Condition check failed: #{e.message}" }
  end

  def analyze_feedback(input)
    return mock_feedback_analysis(input) unless api_configured?

    prompt = build_feedback_prompt(input)
    result = call_claude_api(prompt, "analyze_feedback")

    if result[:success]
      parse_feedback_response(result[:data])
    else
      { success: false, error: result[:error] }
    end
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.analyze_feedback error: #{e.message}")
    { success: false, error: "Feedback analysis failed: #{e.message}" }
  end

  private

  def api_configured?
    ENV["ANTHROPIC_API_KEY"].present?
  end

  def call_claude_api(prompt, operation)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
    request["anthropic-version"] = "2023-06-01"

    request.body = {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      messages: [{ role: "user", content: prompt }]
    }.to_json

    response = http.request(request)

    if response.code.to_i == 200
      data = JSON.parse(response.body)
      text = data.dig("content", 0, "text")
      { success: true, data: text }
    else
      Rails.logger.error("Claude API error for #{operation}: #{response.code} - #{response.body}")
      { success: false, error: "API returned #{response.code}" }
    end
  end

  # ============ Level Test ============

  def build_level_test_prompt(input)
    <<~PROMPT
      You are an expert fitness coach. Analyze the following user profile and determine their training level.

      User Profile:
      - Experience Level: #{input[:experience_level]}
      - Workout Frequency: #{input[:workout_frequency]} times per week
      - Strength Level: #{input[:strength_level]}
      - Endurance Level: #{input[:endurance_level]}
      - Injury History: #{input[:injury_history]&.join(", ") || "None"}
      - Fitness Goals: #{input[:fitness_goals]&.join(", ")}
      - Available Equipment: #{input[:available_equipment]&.join(", ") || "Basic"}

      Respond ONLY with valid JSON in this exact format:
      ```json
      {
        "level": "BEGINNER" or "INTERMEDIATE" or "ADVANCED",
        "confidence": 0.0-1.0,
        "reasoning": "Explanation for the level determination",
        "fitnessFactors": {
          "strength": 0-10,
          "endurance": 0-10,
          "flexibility": 0-10,
          "balance": 0-10,
          "coordination": 0-10
        },
        "recommendations": ["recommendation1", "recommendation2", "recommendation3"]
      }
      ```
    PROMPT
  end

  def parse_level_test_response(text)
    json = extract_json(text)
    {
      success: true,
      level: json["level"],
      confidence: json["confidence"],
      reasoning: json["reasoning"],
      fitness_factors: {
        strength: json.dig("fitnessFactors", "strength") || 5.0,
        endurance: json.dig("fitnessFactors", "endurance") || 5.0,
        flexibility: json.dig("fitnessFactors", "flexibility") || 5.0,
        balance: json.dig("fitnessFactors", "balance") || 5.0,
        coordination: json.dig("fitnessFactors", "coordination") || 5.0
      },
      recommendations: json["recommendations"] || []
    }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse level test response: #{e.message}")
    { success: false, error: "Failed to parse AI response" }
  end

  def mock_level_test_result(input)
    level = case input[:experience_level]&.upcase
            when "ADVANCED" then "ADVANCED"
            when "INTERMEDIATE" then "INTERMEDIATE"
            else "BEGINNER"
            end

    {
      success: true,
      level: level,
      confidence: 0.85,
      reasoning: "Based on your self-reported experience level and workout frequency.",
      fitness_factors: {
        strength: 5.0,
        endurance: 5.0,
        flexibility: 5.0,
        balance: 5.0,
        coordination: 5.0
      },
      recommendations: [
        "Start with a consistent workout schedule",
        "Focus on proper form before increasing weight",
        "Include both strength and cardio training"
      ]
    }
  end

  # ============ Condition Check ============

  def build_condition_prompt(input)
    <<~PROMPT
      You are an expert fitness coach. Based on the user's current condition, provide workout adaptations.

      Current Condition:
      - Energy Level: #{input[:energy_level]}/5
      - Stress Level: #{input[:stress_level]}/5
      - Sleep Quality: #{input[:sleep_quality]}/5
      - Motivation: #{input[:motivation]}/5
      - Available Time: #{input[:available_time]} minutes
      - Muscle Soreness: #{input[:soreness]&.to_json || "None reported"}
      - Notes: #{input[:notes] || "None"}

      Respond ONLY with valid JSON in this exact format:
      ```json
      {
        "adaptations": ["adaptation1", "adaptation2"],
        "intensityModifier": 0.5-1.5,
        "durationModifier": 0.7-1.3,
        "exerciseModifications": ["modification1", "modification2"],
        "restRecommendations": ["rest1", "rest2"]
      }
      ```
    PROMPT
  end

  def parse_condition_response(text)
    json = extract_json(text)
    {
      success: true,
      adaptations: json["adaptations"] || [],
      intensity_modifier: json["intensityModifier"] || 1.0,
      duration_modifier: json["durationModifier"] || 1.0,
      exercise_modifications: json["exerciseModifications"] || [],
      rest_recommendations: json["restRecommendations"] || []
    }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse condition response: #{e.message}")
    { success: false, error: "Failed to parse AI response" }
  end

  def mock_condition_result(input)
    energy = input[:energy_level] || 3
    stress = input[:stress_level] || 3
    sleep = input[:sleep_quality] || 3

    # Calculate modifiers based on condition
    avg_condition = (energy + (6 - stress) + sleep) / 3.0
    intensity_modifier = 0.5 + (avg_condition / 5.0) * 0.5
    duration_modifier = 0.7 + (avg_condition / 5.0) * 0.3

    adaptations = []
    adaptations << "Reduce workout intensity" if energy < 3
    adaptations << "Include stress-relief exercises" if stress > 3
    adaptations << "Shorten workout duration" if sleep < 3
    adaptations << "Standard workout recommended" if adaptations.empty?

    {
      success: true,
      adaptations: adaptations,
      intensity_modifier: intensity_modifier.round(2),
      duration_modifier: duration_modifier.round(2),
      exercise_modifications: [],
      rest_recommendations: stress > 3 ? [ "Take extra rest between sets" ] : []
    }
  end

  # ============ Feedback Analysis ============

  def build_feedback_prompt(input)
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

  def parse_feedback_response(text)
    json = extract_json(text)
    {
      success: true,
      insights: json["insights"] || [],
      adaptations: json["adaptations"] || [],
      next_workout_recommendations: json["nextWorkoutRecommendations"] || []
    }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse feedback response: #{e.message}")
    { success: false, error: "Failed to parse AI response" }
  end

  def mock_feedback_analysis(input)
    rating = input[:rating] || 3
    insights = []
    adaptations = []
    recommendations = []

    if rating >= 4
      insights << "User found the workout effective"
      recommendations << "Continue with similar intensity"
    elsif rating <= 2
      insights << "User struggled with the workout"
      adaptations << "Consider reducing intensity"
      recommendations << "Focus on form and technique"
    else
      insights << "Moderate satisfaction with workout"
      recommendations << "Gradually increase challenge"
    end

    case input[:feedback_type]
    when "DIFFICULTY"
      adaptations << rating > 3 ? "Increase difficulty next time" : "Reduce difficulty next time"
    when "TIME"
      recommendations << rating > 3 ? "Duration is appropriate" : "Adjust workout duration"
    end

    {
      success: true,
      insights: insights,
      adaptations: adaptations,
      next_workout_recommendations: recommendations
    }
  end

  # ============ Routine Generation ============

  def generate_routine(user:, day_of_week: nil, condition_inputs: {})
    AiTrainer.generate_routine(
      user: user,
      day_of_week: day_of_week,
      condition_inputs: condition_inputs
    )
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.generate_routine error: #{e.message}")
    { success: false, error: "Routine generation failed: #{e.message}" }
  end

  # ============ Level Test ============

  def generate_level_test_for_user(user)
    AiTrainer.generate_level_test(user: user)
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.generate_level_test error: #{e.message}")
    { success: false, error: "Level test generation failed: #{e.message}" }
  end

  def evaluate_level_test_results(user:, test_results:)
    result = AiTrainer.evaluate_level_test(user: user, test_results: test_results)

    # Update user profile if passed
    if result[:passed] && user.user_profile
      user.user_profile.update!(
        current_level: result[:new_level],
        last_level_test_at: Time.current
      )
    end

    result
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.evaluate_level_test error: #{e.message}")
    { success: false, error: "Level test evaluation failed: #{e.message}" }
  end

  def check_eligibility(user)
    AiTrainer.check_test_eligibility(user: user)
  rescue StandardError => e
    Rails.logger.error("AiTrainerService.check_eligibility error: #{e.message}")
    { eligible: false, reason: "Error checking eligibility: #{e.message}" }
  end

  # ============ Helpers ============

  def extract_json(text)
    # Try to extract JSON from markdown code blocks first
    if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
      JSON.parse(Regexp.last_match(1))
    else
      # Try to find JSON object directly
      json_match = text.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m)
      raise JSON::ParserError, "No JSON found in response" unless json_match

      JSON.parse(json_match[0])
    end
  end
end
