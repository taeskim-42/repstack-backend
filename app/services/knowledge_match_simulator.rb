# frozen_string_literal: true

# Simulates users of different levels searching for exercise knowledge
# Tests if exercise_name and summary are properly matched
class KnowledgeMatchSimulator
  EXERCISES = %w[
    bench_press
    squat
    deadlift
    lat_pulldown
    shoulder_press
    bicep_curl
    leg_press
    dumbbell_row
    plank
    lunge
  ].freeze

  LEVELS = {
    beginner: {
      korean: "초보자",
      criteria: "기본 자세, 동작 방법, 주의사항",
      reject_if: "너무 전문적이거나 고급 기술"
    },
    intermediate: {
      korean: "중급자",
      criteria: "세부 기술, 변형 동작, 근육별 자극법",
      reject_if: "너무 기초적이거나 운동과 무관한 일반론"
    },
    advanced: {
      korean: "고급자",
      criteria: "미세 조정, 고급 테크닉, 전문 팁",
      reject_if: "해당 운동과 직접 관련 없는 일반적인 내용"
    }
  }.freeze

  class << self
    # Run simulation for all levels in parallel-ready format
    def run_all_levels(exercises: EXERCISES, samples_per_exercise: 3)
      results = {}

      LEVELS.keys.each do |level|
        results[level] = run(level: level, exercises: exercises, samples_per_exercise: samples_per_exercise)
      end

      # Aggregate bad matches across all levels
      all_bad_ids = results.values.flat_map { |r| r[:bad_match_samples].map { |s| s[:chunk_id] } }.uniq

      {
        levels: results,
        summary: {
          total_tested: results.values.sum { |r| r[:total_chunks] },
          total_good: results.values.sum { |r| r[:good_matches] },
          total_bad: results.values.sum { |r| r[:bad_matches] },
          unique_bad_chunk_ids: all_bad_ids,
          unique_bad_count: all_bad_ids.size
        }
      }
    end

    # Run simulation for specific level
    def run(level: :beginner, exercises: EXERCISES, samples_per_exercise: 5)
      level_config = LEVELS[level]
      results = {
        level: level,
        level_korean: level_config[:korean],
        tested_exercises: [],
        total_chunks: 0,
        good_matches: 0,
        bad_matches: 0,
        bad_match_samples: []
      }

      exercises.each do |exercise_name|
        test_exercise(exercise_name, samples_per_exercise, results, level, level_config)
      end

      results[:match_rate] = results[:total_chunks] > 0 ?
        (results[:good_matches].to_f / results[:total_chunks] * 100).round(1) : 0

      results
    end

    private

    def test_exercise(exercise_name, limit, results, level, level_config)
      chunks = FitnessKnowledgeChunk
        .where("? = ANY(string_to_array(exercise_name, ', ')) OR exercise_name = ?", exercise_name, exercise_name)
        .order("RANDOM()")
        .limit(limit)

      return if chunks.empty?

      exercise_result = {
        exercise: exercise_name,
        found_chunks: chunks.count,
        samples: []
      }

      chunks.each do |chunk|
        assessment = assess_match(exercise_name, chunk, level, level_config)
        exercise_result[:samples] << assessment

        results[:total_chunks] += 1
        if assessment[:is_good_match]
          results[:good_matches] += 1
        else
          results[:bad_matches] += 1
          results[:bad_match_samples] << assessment if results[:bad_match_samples].size < 20
        end
      end

      results[:tested_exercises] << exercise_result
    end

    def assess_match(exercise_name, chunk, level, level_config)
      prompt = build_assessment_prompt(exercise_name, chunk, level_config)
      response = call_ai(prompt)

      is_good = response[:success] && response[:content]&.strip&.upcase&.start_with?("YES")

      {
        level: level,
        exercise: exercise_name,
        chunk_id: chunk.id,
        chunk_exercise_name: chunk.exercise_name,
        summary: chunk.summary&.truncate(150),
        is_good_match: is_good,
        ai_reason: response[:content]&.truncate(100)
      }
    end

    def build_assessment_prompt(exercise_name, chunk, level_config)
      korean_name = exercise_korean_name(exercise_name)

      <<~PROMPT
        나는 #{level_config[:korean]}야. "#{korean_name}" 운동을 검색했어.

        [검색 결과]
        #{chunk.summary}

        #{level_config[:korean]}가 찾는 정보: #{level_config[:criteria]}
        이런건 필요없어: #{level_config[:reject_if]}

        이 검색 결과가 #{korean_name} 운동을 하려는 #{level_config[:korean]}에게 도움이 돼?
        YES 또는 NO로 답하고 짧은 이유.
      PROMPT
    end

    def exercise_korean_name(english_name)
      {
        "bench_press" => "벤치프레스",
        "squat" => "스쿼트",
        "deadlift" => "데드리프트",
        "lat_pulldown" => "랫풀다운",
        "shoulder_press" => "숄더프레스",
        "bicep_curl" => "바이셉컬",
        "leg_press" => "레그프레스",
        "dumbbell_row" => "덤벨로우",
        "plank" => "플랭크",
        "lunge" => "런지",
        "incline_bench_press" => "인클라인 벤치프레스",
        "pull_up" => "풀업",
        "dip" => "딥스"
      }[english_name] || english_name
    end

    def call_ai(prompt)
      AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :knowledge_cleanup,
        system: "운동 지식 평가자. YES/NO로 시작하고 짧게 이유 설명."
      )
    end
  end
end
