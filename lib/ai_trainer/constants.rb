# frozen_string_literal: true

module AiTrainer
  module Constants
    # ============================================================
    # FITNESS FACTORS (체력요인)
    # ============================================================
    FITNESS_FACTORS = {
      strength: {
        id: "FF01",
        korean: "근력",
        description: "Maximum force production",
        days: [ 1, 4 ], # Monday, Thursday
        training_method: "fixed_sets_reps",
        typical_bpm: 30,
        typical_rest: 60
      },
      muscular_endurance: {
        id: "FF02",
        korean: "근지구력",
        description: "Sustained muscle performance",
        days: [ 2 ], # Tuesday
        training_method: "total_reps_fill",
        typical_bpm: 30,
        typical_rest: 30
      },
      sustainability: {
        id: "FF03",
        korean: "지속력",
        description: "Continuous performance capacity",
        days: [ 3 ], # Wednesday
        training_method: "max_sets_at_fixed_reps",
        typical_bpm: 30,
        typical_rest: 45
      },
      power: {
        id: "FF04",
        korean: "순발력",
        description: "Explosive force production",
        days: [ 1 ], # Monday (intermediate+)
        training_method: "explosive",
        typical_bpm: nil,
        typical_rest: 90
      },
      cardiovascular: {
        id: "FF05",
        korean: "심폐지구력",
        description: "Heart and lung endurance",
        days: [ 5 ], # Friday
        training_method: "tabata",
        typical_bpm: nil,
        typical_rest: 10
      }
    }.freeze

    # ============================================================
    # LEVELS (레벨 시스템)
    # ============================================================
    LEVELS = {
      1 => { id: "LV01", tier: "beginner", korean_tier: "초급", weight_multiplier: 0.5, description: "Foundation building" },
      2 => { id: "LV02", tier: "beginner", korean_tier: "초급", weight_multiplier: 0.6, description: "Basic movements" },
      3 => { id: "LV03", tier: "intermediate", korean_tier: "중급", weight_multiplier: 0.7, description: "Form refinement" },
      4 => { id: "LV04", tier: "intermediate", korean_tier: "중급", weight_multiplier: 0.8, description: "Volume increase" },
      5 => { id: "LV05", tier: "intermediate", korean_tier: "중급", weight_multiplier: 0.9, description: "Intensity focus" },
      6 => { id: "LV06", tier: "advanced", korean_tier: "고급", weight_multiplier: 1.0, description: "Peak performance" },
      7 => { id: "LV07", tier: "advanced", korean_tier: "고급", weight_multiplier: 1.1, description: "Advanced techniques" },
      8 => { id: "LV08", tier: "advanced", korean_tier: "고급", weight_multiplier: 1.2, description: "Elite training" }
    }.freeze

    # ============================================================
    # GRADES (등급 시스템)
    # ============================================================
    GRADES = {
      normal: { id: "GR01", korean: "정상인", description: "Basic health maintenance", levels: [ 1, 2, 3 ] },
      healthy: { id: "GR02", korean: "건강인", description: "Active lifestyle", levels: [ 4, 5 ] },
      athletic: { id: "GR03", korean: "운동인", description: "Athletic performance", levels: [ 6, 7, 8 ] }
    }.freeze

    # ============================================================
    # EXERCISES CATALOG (운동 목록)
    # ============================================================
    EXERCISES = {
      chest: {
        id_prefix: "EX_CH",
        korean: "가슴",
        exercises: [
          { id: "EX_CH01", name: "푸시업", english: "Push-up", equipment: "none", difficulty: 1 },
          { id: "EX_CH02", name: "BPM 푸시업", english: "BPM Push-up", equipment: "metronome", difficulty: 2 },
          { id: "EX_CH03", name: "샤크 푸시업", english: "Shark Push-up", equipment: "shark_rack", difficulty: 2 },
          { id: "EX_CH04", name: "벤치프레스", english: "Bench Press", equipment: "barbell", difficulty: 3 },
          { id: "EX_CH05", name: "인클라인 벤치프레스", english: "Incline Bench Press", equipment: "barbell", difficulty: 3 },
          { id: "EX_CH06", name: "덤벨 프레스", english: "Dumbbell Press", equipment: "dumbbell", difficulty: 2 },
          { id: "EX_CH07", name: "딥스", english: "Dips", equipment: "dip_station", difficulty: 3 }
        ]
      },
      back: {
        id_prefix: "EX_BK",
        korean: "등",
        exercises: [
          { id: "EX_BK01", name: "턱걸이", english: "Pull-up", equipment: "pull_up_bar", difficulty: 3 },
          { id: "EX_BK02", name: "샤크 턱걸이", english: "Shark Pull-up", equipment: "shark_rack", difficulty: 2 },
          { id: "EX_BK03", name: "렛풀다운", english: "Lat Pulldown", equipment: "cable", difficulty: 2 },
          { id: "EX_BK04", name: "데드리프트", english: "Deadlift", equipment: "barbell", difficulty: 4 },
          { id: "EX_BK05", name: "바벨로우", english: "Barbell Row", equipment: "barbell", difficulty: 3 },
          { id: "EX_BK06", name: "덤벨로우", english: "Dumbbell Row", equipment: "dumbbell", difficulty: 2 }
        ]
      },
      legs: {
        id_prefix: "EX_LG",
        korean: "하체",
        exercises: [
          { id: "EX_LG01", name: "기둥 스쿼트", english: "Pole Squat", equipment: "pole", difficulty: 1 },
          { id: "EX_LG02", name: "맨몸 스쿼트", english: "Bodyweight Squat", equipment: "none", difficulty: 1 },
          { id: "EX_LG03", name: "바벨 스쿼트", english: "Barbell Squat", equipment: "barbell", difficulty: 3 },
          { id: "EX_LG04", name: "런지", english: "Lunge", equipment: "none", difficulty: 2 },
          { id: "EX_LG05", name: "레그프레스", english: "Leg Press", equipment: "machine", difficulty: 2 },
          { id: "EX_LG06", name: "레그컬", english: "Leg Curl", equipment: "machine", difficulty: 2 },
          { id: "EX_LG07", name: "레그익스텐션", english: "Leg Extension", equipment: "machine", difficulty: 2 }
        ]
      },
      shoulders: {
        id_prefix: "EX_SH",
        korean: "어깨",
        exercises: [
          { id: "EX_SH01", name: "오버헤드프레스", english: "Overhead Press", equipment: "barbell", difficulty: 3 },
          { id: "EX_SH02", name: "덤벨 숄더프레스", english: "Dumbbell Shoulder Press", equipment: "dumbbell", difficulty: 2 },
          { id: "EX_SH03", name: "레터럴레이즈", english: "Lateral Raise", equipment: "dumbbell", difficulty: 1 },
          { id: "EX_SH04", name: "페이스풀", english: "Face Pull", equipment: "cable", difficulty: 2 }
        ]
      },
      arms: {
        id_prefix: "EX_AR",
        korean: "팔",
        exercises: [
          { id: "EX_AR01", name: "바벨컬", english: "Barbell Curl", equipment: "barbell", difficulty: 2 },
          { id: "EX_AR02", name: "덤벨컬", english: "Dumbbell Curl", equipment: "dumbbell", difficulty: 1 },
          { id: "EX_AR03", name: "트라이셉 익스텐션", english: "Tricep Extension", equipment: "cable", difficulty: 2 },
          { id: "EX_AR04", name: "해머컬", english: "Hammer Curl", equipment: "dumbbell", difficulty: 1 }
        ]
      },
      core: {
        id_prefix: "EX_CR",
        korean: "복근",
        exercises: [
          { id: "EX_CR01", name: "크런치", english: "Crunch", equipment: "none", difficulty: 1 },
          { id: "EX_CR02", name: "플랭크", english: "Plank", equipment: "none", difficulty: 1 },
          { id: "EX_CR03", name: "레그레이즈", english: "Leg Raise", equipment: "none", difficulty: 2 },
          { id: "EX_CR04", name: "행잉레그레이즈", english: "Hanging Leg Raise", equipment: "pull_up_bar", difficulty: 3 },
          { id: "EX_CR05", name: "싯업", english: "Sit-up", equipment: "none", difficulty: 1 },
          { id: "EX_CR06", name: "바이시클 크런치", english: "Bicycle Crunch", equipment: "none", difficulty: 2 }
        ]
      },
      cardio: {
        id_prefix: "EX_CD",
        korean: "유산소",
        exercises: [
          { id: "EX_CD01", name: "버피", english: "Burpee", equipment: "none", difficulty: 3 },
          { id: "EX_CD02", name: "점핑잭", english: "Jumping Jack", equipment: "none", difficulty: 1 },
          { id: "EX_CD03", name: "마운틴클라이머", english: "Mountain Climber", equipment: "none", difficulty: 2 },
          { id: "EX_CD04", name: "하이니", english: "High Knees", equipment: "none", difficulty: 1 },
          { id: "EX_CD05", name: "스쿼트점프", english: "Squat Jump", equipment: "none", difficulty: 2 }
        ]
      }
    }.freeze

    # ============================================================
    # TRAINING VARIABLES (훈련 변인)
    # ============================================================
    TRAINING_VARIABLES = {
      sets: {
        range: 1..10,
        default_by_factor: {
          strength: 3,
          muscular_endurance: "until_target",
          sustainability: "max_possible",
          power: 5,
          cardiovascular: 8
        }
      },
      reps: {
        range: 1..50,
        default_by_factor: {
          strength: 10,
          muscular_endurance: "max_per_set",
          sustainability: 10,
          power: 5,
          cardiovascular: 20
        }
      },
      weight: {
        formula: {
          bench: ->(height, level) { (height - 100) * LEVELS[level][:weight_multiplier] },
          squat: ->(height, level) { (height - 100 + 20) * LEVELS[level][:weight_multiplier] },
          deadlift: ->(height, level) { (height - 100 + 40) * LEVELS[level][:weight_multiplier] }
        },
        description: "체중 기반 또는 RM 기반 계산"
      },
      rack_position: {
        range: 1..9,
        description: "1칸=최저(최대 가동범위/최고 난이도), 9칸=최고(최소 가동범위/보조)",
        default: 5
      },
      bpm: {
        range: 20..120,
        default_by_level: {
          beginner: 30,
          intermediate: 40,
          advanced: "자유 설정"
        },
        description: "메트로놈 템포 (beats per minute)"
      },
      range_of_motion: {
        options: [ :full, :medium, :short ],
        korean: { full: "풀", medium: "중간", short: "깔" },
        default_by_factor: {
          strength: :full,
          muscular_endurance: :full,
          sustainability: :full,
          power: :medium,
          cardiovascular: :short
        }
      },
      rest: {
        time_based: {
          range: 10..180,
          default_by_factor: {
            strength: 60,
            muscular_endurance: 30,
            sustainability: 45,
            power: 90,
            cardiovascular: 10
          }
        },
        heart_rate_based: {
          enabled: true,
          recovery_threshold_formula: ->(max_hr, percentage) { max_hr * percentage },
          default_percentage: 0.6,
          max_wait_seconds: 180
        }
      }
    }.freeze

    # ============================================================
    # TRAINING METHODS (훈련 방법)
    # ============================================================
    TRAINING_METHODS = {
      fixed_sets_reps: {
        id: "TM01",
        korean: "정해진 세트/횟수",
        description: "Perform exactly X sets of Y reps",
        applies_to: [ :strength ]
      },
      total_reps_fill: {
        id: "TM02",
        korean: "채우기",
        description: "Complete target total reps regardless of sets",
        applies_to: [ :muscular_endurance ]
      },
      max_sets_at_fixed_reps: {
        id: "TM03",
        korean: "지속력 측정",
        description: "How many sets of fixed reps can you sustain?",
        applies_to: [ :sustainability ]
      },
      tabata: {
        id: "TM04",
        korean: "타바타",
        description: "20s work + 10s rest intervals",
        work_duration: 20,
        rest_duration: 10,
        rounds: 8,
        applies_to: [ :cardiovascular ]
      },
      explosive: {
        id: "TM05",
        korean: "폭발적 수행",
        description: "Maximum speed/power per rep with full recovery",
        applies_to: [ :power ]
      }
    }.freeze

    # ============================================================
    # CONDITION INPUTS (컨디션 입력)
    # ============================================================
    CONDITION_INPUTS = {
      sleep: {
        id: "CI01",
        korean: "수면",
        scale: 1..5,
        weight: 0.3,
        description: "Sleep quality last night"
      },
      fatigue: {
        id: "CI02",
        korean: "피로도",
        scale: 1..5,
        weight: 0.25,
        description: "Current fatigue level (1=fresh, 5=exhausted)"
      },
      stress: {
        id: "CI03",
        korean: "스트레스",
        scale: 1..5,
        weight: 0.2,
        description: "Mental stress level"
      },
      soreness: {
        id: "CI04",
        korean: "근육통",
        scale: 1..5,
        weight: 0.15,
        description: "Muscle soreness level"
      },
      motivation: {
        id: "CI05",
        korean: "의욕",
        scale: 1..5,
        weight: 0.1,
        description: "Motivation to workout"
      }
    }.freeze

    # ============================================================
    # CONDITION ADJUSTMENTS (컨디션 조정)
    # ============================================================
    CONDITION_ADJUSTMENTS = {
      excellent: { score_range: 4.0..5.0, volume_modifier: 1.1, intensity_modifier: 1.1, korean: "최상" },
      good: { score_range: 3.0...4.0, volume_modifier: 1.0, intensity_modifier: 1.0, korean: "양호" },
      moderate: { score_range: 2.0...3.0, volume_modifier: 0.85, intensity_modifier: 0.9, korean: "보통" },
      poor: { score_range: 1.0...2.0, volume_modifier: 0.7, intensity_modifier: 0.75, korean: "나쁨" }
    }.freeze

    # ============================================================
    # FEEDBACK CATEGORIES (피드백 카테고리)
    # ============================================================
    FEEDBACK_CATEGORIES = {
      difficulty: { id: "FB01", korean: "난이도", options: %w[too_easy appropriate too_hard] },
      energy: { id: "FB02", korean: "에너지", options: %w[drained okay energized] },
      enjoyment: { id: "FB03", korean: "만족도", scale: 1..5 },
      pain: { id: "FB04", korean: "통증", body_parts: true, scale: 0..10 },
      time: { id: "FB05", korean: "시간", options: %w[too_short appropriate too_long] }
    }.freeze

    # ============================================================
    # LEVEL TEST CRITERIA (승급 시험 기준)
    # ============================================================
    LEVEL_TEST_CRITERIA = {
      1 => { bench_ratio: 0.5, squat_ratio: 0.6, deadlift_ratio: 0.7, description: "기초 체력" },
      2 => { bench_ratio: 0.6, squat_ratio: 0.7, deadlift_ratio: 0.8, description: "기본 근력" },
      3 => { bench_ratio: 0.7, squat_ratio: 0.8, deadlift_ratio: 0.9, description: "중급 입문" },
      4 => { bench_ratio: 0.8, squat_ratio: 0.9, deadlift_ratio: 1.0, description: "중급 기본" },
      5 => { bench_ratio: 0.9, squat_ratio: 1.0, deadlift_ratio: 1.1, description: "중급 완성" },
      6 => { bench_ratio: 1.0, squat_ratio: 1.1, deadlift_ratio: 1.2, description: "고급 입문" },
      7 => { bench_ratio: 1.1, squat_ratio: 1.2, deadlift_ratio: 1.3, description: "고급 기본" },
      8 => { bench_ratio: 1.2, squat_ratio: 1.3, deadlift_ratio: 1.4, description: "엘리트" }
    }.freeze

    # ============================================================
    # WEEKLY STRUCTURE (주간 구조)
    # ============================================================
    WEEKLY_STRUCTURE = {
      1 => { day: "Monday", korean: "월요일", fitness_factor: :strength },
      2 => { day: "Tuesday", korean: "화요일", fitness_factor: :muscular_endurance },
      3 => { day: "Wednesday", korean: "수요일", fitness_factor: :sustainability },
      4 => { day: "Thursday", korean: "목요일", fitness_factor: :strength },
      5 => { day: "Friday", korean: "금요일", fitness_factor: :cardiovascular }
    }.freeze

    # Helper methods
    class << self
      def fitness_factor_for_day(day_number)
        WEEKLY_STRUCTURE.dig(day_number, :fitness_factor)
      end

      def level_info(level)
        LEVELS[level]
      end

      def tier_for_level(level)
        LEVELS.dig(level, :tier)
      end

      def weight_multiplier_for_level(level)
        LEVELS.dig(level, :weight_multiplier) || 1.0
      end

      def exercises_for_muscle(muscle_group)
        EXERCISES.dig(muscle_group.to_sym, :exercises) || []
      end

      def calculate_condition_score(inputs)
        total_weight = CONDITION_INPUTS.values.sum { |v| v[:weight] }
        weighted_sum = 0.0

        CONDITION_INPUTS.each do |key, config|
          value = inputs[key] || 3 # Default to middle value
          # Invert fatigue, stress, soreness (higher = worse)
          adjusted_value = %i[fatigue stress soreness].include?(key) ? (6 - value) : value
          weighted_sum += adjusted_value * config[:weight]
        end

        weighted_sum / total_weight
      end

      def adjustment_for_condition_score(score)
        CONDITION_ADJUSTMENTS.find { |_key, config| config[:score_range].include?(score) }&.last || CONDITION_ADJUSTMENTS[:good]
      end

      def calculate_target_weight(exercise_type:, height:, level:)
        formula = TRAINING_VARIABLES.dig(:weight, :formula, exercise_type.to_sym)
        return nil unless formula

        formula.call(height, level).round(2)
      end

      def training_method_for_factor(factor)
        TRAINING_METHODS.find { |_key, config| config[:applies_to].include?(factor.to_sym) }&.first
      end
    end
  end
end
