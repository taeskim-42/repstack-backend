# frozen_string_literal: true

namespace :knowledge do
  desc "Import workout programs from Excel data into RAG knowledge base"
  task import_programs: :environment do
    puts "Importing workout programs into FitnessKnowledgeChunk..."

    # Create a virtual YouTube video for program knowledge
    channel = YoutubeChannel.find_or_create_by!(
      channel_id: "PROGRAM_KNOWLEDGE",
      name: "운동 프로그램 지식",
      subscribers: 0,
      total_views: 0,
      expertise_area: "routine_design"
    )

    video = YoutubeVideo.find_or_create_by!(
      youtube_channel: channel,
      video_id: "PROGRAM_TEMPLATES",
      youtube_url: "internal://program-templates",
      title: "운동 프로그램 템플릿",
      duration_seconds: 0
    )

    imported_count = 0

    # Import BEGINNER program
    import_program(video, AiTrainer::WorkoutPrograms::BEGINNER, "beginner")
    imported_count += count_exercises(AiTrainer::WorkoutPrograms::BEGINNER)

    # Import INTERMEDIATE program
    import_program(video, AiTrainer::WorkoutPrograms::INTERMEDIATE, "intermediate")
    imported_count += count_exercises(AiTrainer::WorkoutPrograms::INTERMEDIATE)

    # Import ADVANCED program
    import_program(video, AiTrainer::WorkoutPrograms::ADVANCED, "advanced")
    imported_count += count_exercises(AiTrainer::WorkoutPrograms::ADVANCED)

    # Import special programs (심현도, 김성환)
    if defined?(AiTrainer::WorkoutPrograms::SHIMHYUNDO)
      import_special_program(video, AiTrainer::WorkoutPrograms::SHIMHYUNDO, "심현도 무분할")
      imported_count += 10
    end

    if defined?(AiTrainer::WorkoutPrograms::KIM_SUNGHWAN)
      import_special_program(video, AiTrainer::WorkoutPrograms::KIM_SUNGHWAN, "김성환")
      imported_count += 10
    end

    puts "✅ Imported #{imported_count} program knowledge chunks"
  end

  def import_program(video, program, difficulty)
    program_name = program[:korean] || program[:level]
    weeks = program[:weeks] || 4

    program[:program].each do |week_num, week_data|
      week_data.each do |day_num, day_data|
        training_type = day_data[:training_type]
        training_info = AiTrainer::WorkoutPrograms::TRAINING_TYPES[training_type] || {}

        # Build content describing this day's workout
        content = build_day_content(program_name, week_num, day_num, day_data, training_info)

        # Extract exercise names
        exercise_names = day_data[:exercises].map { |ex| ex[:name] }.join(", ")

        # Create knowledge chunk
        FitnessKnowledgeChunk.find_or_create_by!(
          youtube_video: video,
          knowledge_type: "routine_design",
          content: content,
          summary: "#{program_name} #{week_num}주차 #{day_num}일: #{training_info[:korean] || training_type}",
          exercise_name: exercise_names,
          difficulty_level: difficulty,
          timestamp_start: 0
        )
      end
    end
  end

  def build_day_content(program_name, week_num, day_num, day_data, training_info)
    lines = []
    lines << "## #{program_name} - #{week_num}주차 #{day_num}일차"
    lines << ""
    lines << "### 훈련 유형: #{training_info[:korean] || day_data[:training_type]}"
    lines << training_info[:description] if training_info[:description]
    lines << ""
    lines << "### 운동 목록"

    day_data[:exercises].each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      details << "BPM #{ex[:bpm]}" if ex[:bpm]
      details << "무게: #{ex[:weight]}" if ex[:weight]
      details << "ROM: #{ex[:rom]}" if ex[:rom]

      exercise_line += " - #{details.join(', ')}" if details.any?
      exercise_line += "\n   방법: #{ex[:how_to]}" if ex[:how_to]

      lines << exercise_line
    end

    if day_data[:purpose]
      lines << ""
      lines << "### 목적"
      lines << day_data[:purpose]
    end

    lines.join("\n")
  end

  def import_special_program(video, program, name)
    content = build_special_program_content(program, name)

    FitnessKnowledgeChunk.find_or_create_by!(
      youtube_video: video,
      knowledge_type: "routine_design",
      content: content,
      summary: "#{name} 루틴 프로그램",
      exercise_name: extract_all_exercises(program),
      difficulty_level: "all",
      timestamp_start: 0
    )
  end

  def build_special_program_content(program, name)
    lines = ["## #{name} 운동 프로그램", ""]

    if program[:description]
      lines << program[:description]
      lines << ""
    end

    # Handle different program structures
    if program[:levels]
      program[:levels].each do |level_num, level_data|
        lines << "### 레벨 #{level_num}"
        lines.concat(format_exercises(level_data[:exercises])) if level_data[:exercises]
        lines << ""
      end
    elsif program[:phases]
      program[:phases].each do |phase_name, phase_data|
        lines << "### #{phase_name} 페이즈"
        lines.concat(format_exercises(phase_data[:exercises])) if phase_data[:exercises]
        lines << ""
      end
    end

    lines.join("\n")
  end

  def format_exercises(exercises)
    return [] unless exercises

    exercises.map.with_index do |ex, idx|
      line = "#{idx + 1}. #{ex[:name]}"
      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      line += " - #{details.join(', ')}" if details.any?
      line
    end
  end

  def extract_all_exercises(program)
    exercises = []

    if program[:levels]
      program[:levels].each_value do |level_data|
        exercises.concat(level_data[:exercises]&.map { |ex| ex[:name] } || [])
      end
    elsif program[:phases]
      program[:phases].each_value do |phase_data|
        exercises.concat(phase_data[:exercises]&.map { |ex| ex[:name] } || [])
      end
    end

    exercises.uniq.join(", ")
  end

  def count_exercises(program)
    count = 0
    program[:program].each_value do |week|
      count += week.keys.count
    end
    count
  end
end
