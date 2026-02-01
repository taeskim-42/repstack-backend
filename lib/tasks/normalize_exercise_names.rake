# frozen_string_literal: true

require_relative "../ai_trainer/exercise_name_normalizer"

namespace :exercises do
  desc "Normalize all exercise names to Korean"
  task normalize_names: :environment do
    puts "=" * 60
    puts "Exercise Name Normalization"
    puts "=" * 60
    puts

    # Find exercises with English names (no Korean characters)
    english_exercises = Exercise.where.not("display_name ~ ?", "[가-힣]")
                                .or(Exercise.where(display_name: nil))

    puts "영어 이름 운동 수: #{english_exercises.count}"
    puts

    updated_count = 0
    skipped_count = 0

    english_exercises.find_each do |exercise|
      current_name = exercise.display_name || exercise.name

      # Try to normalize using shared module
      korean_name = AiTrainer::ExerciseNameNormalizer.normalize(current_name)

      # Only update if we found a Korean translation
      if korean_name != current_name && AiTrainer::ExerciseNameNormalizer.korean?(korean_name)
        puts "✓ #{current_name} → #{korean_name}"
        exercise.update!(display_name: korean_name)
        updated_count += 1
      else
        puts "✗ #{current_name} (매핑 없음)"
        skipped_count += 1
      end
    end

    puts
    puts "=" * 60
    puts "결과"
    puts "=" * 60
    puts "변환 완료: #{updated_count}"
    puts "매핑 없음: #{skipped_count}"
    puts
    puts "매핑이 없는 운동은 lib/ai_trainer/exercise_name_normalizer.rb의 ENGLISH_TO_KOREAN에 추가해주세요."
  end

  desc "List exercises with non-Korean display names"
  task list_english_names: :environment do
    exercises = Exercise.all.select do |e|
      name = e.display_name || e.name
      !AiTrainer::ExerciseNameNormalizer.korean?(name)
    end

    puts "영어 이름 운동 목록 (#{exercises.count}개):"
    puts "-" * 40
    exercises.each do |e|
      puts "- #{e.display_name || e.name} (ID: #{e.id})"
    end
  end

  desc "Show exercise name statistics"
  task name_stats: :environment do
    total = Exercise.count

    korean_count = Exercise.all.count do |e|
      name = e.display_name || e.name
      AiTrainer::ExerciseNameNormalizer.korean?(name)
    end
    english_count = total - korean_count

    puts "=" * 40
    puts "Exercise Name Statistics"
    puts "=" * 40
    puts "총 운동 수: #{total}"
    puts "한글 이름: #{korean_count} (#{(korean_count.to_f / total * 100).round(1)}%)"
    puts "영어 이름: #{english_count} (#{(english_count.to_f / total * 100).round(1)}%)"
  end

  desc "Preview normalization without making changes"
  task preview_normalization: :environment do
    puts "=" * 60
    puts "Exercise Name Normalization Preview (Dry Run)"
    puts "=" * 60
    puts

    english_exercises = Exercise.where.not("display_name ~ ?", "[가-힣]")
                                .or(Exercise.where(display_name: nil))

    would_update = 0
    no_mapping = 0

    english_exercises.find_each do |exercise|
      current_name = exercise.display_name || exercise.name
      korean_name = AiTrainer::ExerciseNameNormalizer.normalize(current_name)

      if korean_name != current_name && AiTrainer::ExerciseNameNormalizer.korean?(korean_name)
        puts "[WOULD UPDATE] #{current_name} → #{korean_name}"
        would_update += 1
      else
        puts "[NO MAPPING] #{current_name}"
        no_mapping += 1
      end
    end

    puts
    puts "=" * 60
    puts "예상 결과"
    puts "=" * 60
    puts "변환 예정: #{would_update}"
    puts "매핑 없음: #{no_mapping}"
    puts
    puts "실제 변환하려면: rails exercises:normalize_names"
  end
end
