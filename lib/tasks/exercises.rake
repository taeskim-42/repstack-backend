# frozen_string_literal: true

namespace :exercises do
  desc "Sync exercises from FitnessKnowledgeChunk data"
  task sync_from_chunks: :environment do
    puts "=" * 60
    puts "Syncing Exercises from Knowledge Chunks"
    puts "=" * 60

    # Generic terms to exclude (not real exercises)
    generic_patterns = %w[
      general n/a nutrition supplementation fitness bodybuilding
      recovery performance diet training_principle routine
      workout bulking cutting meal hydration sleep stretching
      warmup cooldown cardio_general strength_training weight_training
      pre_workout post_workout competition_prep
    ]

    # Get all unique exercise names from chunks
    chunk_exercises = FitnessKnowledgeChunk
      .where.not(exercise_name: [nil, ""])
      .group(:exercise_name)
      .count
      .sort_by { |_, v| -v }

    puts "Total unique exercise names in chunks: #{chunk_exercises.count}"

    # Filter out generic terms
    real_exercises = chunk_exercises.reject do |name, _|
      name_lower = name.downcase
      generic_patterns.any? { |g| name_lower.include?(g) }
    end

    puts "Real exercises (after filtering): #{real_exercises.count}"

    # Get existing exercise names
    existing = Exercise.pluck(:english_name).map(&:downcase)
    puts "Existing exercises in table: #{existing.count}"

    # Find missing exercises
    missing = real_exercises.reject do |name, _|
      existing.any? { |en| name.downcase == en || name.downcase.gsub("_", "") == en.gsub("_", "") }
    end

    puts "Missing exercises to create: #{missing.count}"
    puts "-" * 60

    created = 0
    skipped = 0

    missing.each do |exercise_name, chunk_count|
      # Skip if too few chunks (likely noise)
      if chunk_count < 3
        skipped += 1
        next
      end

      # Infer muscle group from chunk data
      muscle_group = infer_muscle_group(exercise_name)

      # Generate Korean name
      korean_name = generate_korean_name(exercise_name)

      # Create exercise
      exercise = Exercise.new(
        name: korean_name,
        english_name: exercise_name,
        muscle_group: muscle_group,
        difficulty: 3, # default medium
        min_level: 1,
        ai_generated: true,
        active: true
      )

      if exercise.save
        puts "✓ Created: #{exercise_name} (#{muscle_group}) - #{chunk_count} chunks"
        created += 1
      else
        puts "✗ Failed: #{exercise_name} - #{exercise.errors.full_messages.join(", ")}"
        skipped += 1
      end
    end

    puts "-" * 60
    puts "Created: #{created}, Skipped: #{skipped}"
    puts "Total exercises now: #{Exercise.count}"
  end

  desc "Link video references to exercises from chunks"
  task link_video_references: :environment do
    puts "=" * 60
    puts "Linking Video References to Exercises"
    puts "=" * 60

    linked = 0
    Exercise.find_each do |exercise|
      # Find matching chunks
      chunks = FitnessKnowledgeChunk
        .joins(:youtube_video)
        .where(exercise_name: exercise.english_name)
        .where.not(youtube_videos: { video_id: nil })
        .select("fitness_knowledge_chunks.*, youtube_videos.video_id, youtube_videos.title as video_title")
        .limit(5) # Max 5 video references per exercise

      next if chunks.empty?

      chunks.each do |chunk|
        exercise.add_video_reference(
          video_id: chunk.video_id,
          title: chunk.video_title,
          url: "https://www.youtube.com/watch?v=#{chunk.video_id}",
          timestamp_start: chunk.timestamp_start,
          chunk_id: chunk.id
        )
      end

      if exercise.video_references.any? && exercise.changed?
        exercise.save!
        print "."
        linked += 1
      end
    end

    puts "\n"
    puts "Linked video references for #{linked} exercises"
  end

  desc "Full sync: create missing exercises + link video references"
  task sync: :environment do
    Rake::Task["exercises:sync_from_chunks"].invoke
    puts "\n"
    Rake::Task["exercises:link_video_references"].invoke
  end

  desc "Show exercise sync statistics"
  task stats: :environment do
    puts "\n📊 Exercise Statistics:"
    puts "  Total exercises: #{Exercise.count}"
    puts "    - Manual: #{Exercise.where(ai_generated: false).count}"
    puts "    - AI Generated: #{Exercise.where(ai_generated: true).count}"
    puts "  With video references: #{Exercise.where.not(video_references: []).count}"

    puts "\n  By muscle group:"
    Exercise.group(:muscle_group).count.sort_by { |_, v| -v }.each do |group, count|
      puts "    - #{group}: #{count}"
    end

    # Chunk coverage
    total_chunk_exercises = FitnessKnowledgeChunk.where.not(exercise_name: nil).distinct.count(:exercise_name)
    matched = FitnessKnowledgeChunk
      .where.not(exercise_name: nil)
      .where(exercise_name: Exercise.pluck(:english_name))
      .distinct
      .count(:exercise_name)

    puts "\n  Chunk coverage: #{matched}/#{total_chunk_exercises} (#{(matched.to_f / total_chunk_exercises * 100).round(1)}%)"
  end

  private

  def infer_muscle_group(exercise_name)
    name = exercise_name.downcase

    # Muscle group inference rules
    case name
    when /bench|chest|fly|push.*up|dip|pec/
      "chest"
    when /row|pull.*up|pulldown|lat|back|deadlift|shrug/
      "back"
    when /squat|leg|lunge|calf|hamstring|quad|glute|hip/
      "legs"
    when /shoulder|press|lateral.*raise|rear.*delt|front.*raise|overhead/
      "shoulders"
    when /curl|bicep|tricep|arm|extension|skull.*crusher|pushdown/
      "arms"
    when /crunch|plank|ab|core|oblique|sit.*up/
      "core"
    when /run|bike|jump|cardio|burpee/
      "cardio"
    else
      # Default: check chunk data for this exercise
      chunk = FitnessKnowledgeChunk.where(exercise_name: exercise_name).where.not(muscle_group: nil).first
      chunk&.muscle_group || "chest" # fallback
    end
  end

  def generate_korean_name(english_name)
    # Common exercise name mappings
    translations = {
      "t_bar_row" => "티바 로우",
      "chest_press" => "체스트 프레스",
      "dumbbell_fly" => "덤벨 플라이",
      "cable_crossover" => "케이블 크로스오버",
      "bicep_curl" => "바이셉 컬",
      "behind_neck_press" => "비하인드 넥 프레스",
      "upright_row" => "업라이트 로우",
      "one_arm_dumbbell_row" => "원암 덤벨 로우",
      "front_press" => "프론트 프레스",
      "chest_fly" => "체스트 플라이",
      "cable_row" => "케이블 로우",
      "bulgarian_split_squat" => "불가리안 스플릿 스쿼트",
      "cable_fly" => "케이블 플라이",
      "high_row" => "하이 로우",
      "seated_row" => "시티드 로우",
      "face_pull" => "페이스 풀",
      "tricep_pushdown" => "트라이셉 푸시다운",
      "hammer_curl" => "해머 컬",
      "preacher_curl" => "프리처 컬",
      "skull_crusher" => "스컬 크러셔",
      "leg_curl" => "레그 컬",
      "calf_raise" => "카프 레이즈",
      "hip_thrust" => "힙 쓰러스트",
      "romanian_deadlift" => "루마니안 데드리프트",
      "sumo_deadlift" => "스모 데드리프트",
      "front_squat" => "프론트 스쿼트",
      "hack_squat" => "핵 스쿼트",
      "goblet_squat" => "고블릿 스쿼트",
      "machine_press" => "머신 프레스",
      "pec_deck" => "펙덱 플라이",
      "reverse_fly" => "리버스 플라이",
      "close_grip_bench_press" => "클로즈그립 벤치프레스",
      "incline_dumbbell_press" => "인클라인 덤벨 프레스",
      "decline_bench_press" => "디클라인 벤치프레스"
    }

    return translations[english_name] if translations[english_name]

    # Auto-generate Korean name from English
    english_name
      .gsub("_", " ")
      .split
      .map(&:capitalize)
      .join(" ")
  end
end
