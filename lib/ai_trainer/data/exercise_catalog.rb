# frozen_string_literal: true

module AiTrainer
  module Data
    module ExerciseCatalog
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
    end
  end
end
