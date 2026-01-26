# frozen_string_literal: true

module AiTrainer
  # Structured workout programs based on Excel 운동프로그램
  # Programs include:
  # - 운동프로그램[초급/중급/고급].xlsx
  # - 심현도_무분할 루틴.xlsx (8 levels)
  # - 김성환님 운동루틴.xlsx (phase-based)
  module WorkoutPrograms
    # Training types
    TRAINING_TYPES = {
      strength: { korean: "근력", description: "BPM 맞춰서 정해진 세트/횟수 수행" },
      strength_power: { korean: "근력 + 순발력", description: "점진적 증량 후 드랍" },
      muscular_endurance: { korean: "근지구력", description: "목표 횟수 채우기" },
      sustainability: { korean: "지속력", description: "몇 세트까지 지속 가능한지 확인" },
      cardiovascular: { korean: "심폐지구력", description: "타바타 20초 운동 + 10초 휴식" },
      form_practice: { korean: "자세연습", description: "트레이너 지도 하에 자세 연습" },
      dropset: { korean: "드랍세트", description: "점진적 무게 감량하며 반복" },
      bingo: { korean: "빙고", description: "여러 무게로 이어서 수행" }
    }.freeze

    # Range of motion options
    ROM = {
      full: { korean: "풀", description: "전체 가동범위" },
      medium: { korean: "중(몸-중)", description: "중간 가동범위" },
      short: { korean: "깔", description: "짧은 가동범위 (깔짝)" }
    }.freeze

    # ============================================================
    # BEGINNER PROGRAM (초급) - 4 weeks
    # Source: 운동프로그램[초급].xlsx
    # ============================================================
    BEGINNER = {
      level: "beginner",
      korean: "초급",
      numeric_levels: [1, 2],
      weeks: 4,
      program: {
        1 => {
          1 => {
            training_type: :strength,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 3, reps: 10, weight: "10회 가능한 칸", bpm: 30, rom: :full },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 3, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 3, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 100, weight: nil, bpm: nil, rom: :full, how_to: "100개 채우기" }
            ]
          },
          2 => {
            training_type: :muscular_endurance,
            exercises: [
              { name: "푸시업", target: "가슴", sets: nil, reps: 100, weight: "10회 가능한 칸 + 1(더 쉽게)", bpm: nil, rom: :full, how_to: "운동 100개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 100, weight: nil, bpm: nil, rom: :full, how_to: "운동 100개 채우기" },
              { name: "기둥 스쿼트", target: "하체", sets: nil, reps: 100, weight: nil, bpm: nil, rom: :full, how_to: "운동 100개 채우기" },
              { name: "복근", target: "복근", sets: nil, reps: 100, weight: nil, bpm: nil, rom: :full, how_to: "100개 채우기" }
            ],
            purpose: "각 세트, 최대 갯수를 수행한다. 10개 10세트 해야지 (X) 23, 18, 15 ... (O)"
          },
          3 => {
            training_type: :sustainability,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 5, reps: 10, weight: "10회 가능한 칸", bpm: 30, rom: :full },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 5, reps: 10, weight: "10회 가능한 무게로", bpm: 30, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 5, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: 10, reps: 10, weight: nil, bpm: nil, rom: :full, how_to: "100개 채우기" }
            ],
            purpose: "각 세트에서 10개를 몇 세트까지 지속할 수 있는지 확인"
          },
          4 => {
            training_type: :strength,
            exercises: [
              { name: "푸시업", target: "가슴", sets: 4, reps: 10, weight: "10회 가능한 칸", bpm: nil, rom: :full },
              { name: "렛풀다운", target: "등", sets: 4, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "기둥 스쿼트", target: "하체", sets: 4, reps: 10, weight: nil, bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 100, weight: nil, bpm: nil, rom: :full, how_to: "100개 채우기" }
            ]
          },
          5 => {
            training_type: :cardiovascular,
            exercises: [
              { name: "타바타 푸시업", target: "가슴", sets: nil, reps: 100, weight: "10회 가능한 칸 + 2(더 쉽게)", bpm: nil, rom: :short, work_seconds: 20, how_to: "100개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 100, weight: "10회 가능한 무게로", bpm: nil, rom: :short, work_seconds: 20, how_to: "100개 채우기" },
              { name: "타바타 기둥 스쿼트", target: "하체", sets: nil, reps: 100, weight: nil, bpm: nil, rom: :short, work_seconds: 20, how_to: "100개 채우기" }
            ],
            purpose: "20초 운동 + 10초 휴식, 운동 시간 동안 최대한의 힘을 쏟아내는 것이 중요"
          }
        },
        2 => {
          1 => {
            training_type: :strength,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 5, reps: 10, weight: "10회 가능한 칸", bpm: 30, rom: :full },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 5, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 5, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 150, weight: nil, bpm: nil, rom: :full, how_to: "150개 채우기" },
              { name: "데드리프트", target: "등", sets: 3, reps: 10, weight: "20kg", bpm: nil, rom: nil, training_type: :form_practice }
            ]
          },
          2 => {
            training_type: :muscular_endurance,
            exercises: [
              { name: "푸시업", target: "가슴", sets: nil, reps: 150, weight: "10회 가능한 칸 + 1", bpm: nil, rom: :short, how_to: "150개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 150, weight: nil, bpm: nil, rom: :short, how_to: "150개 채우기" },
              { name: "기둥 스쿼트", target: "하체", sets: nil, reps: 150, weight: nil, bpm: nil, rom: :short, how_to: "150개 채우기" },
              { name: "복근", target: "복근", sets: nil, reps: 150, weight: nil, bpm: nil, rom: :full, how_to: "150개 채우기" },
              { name: "데드리프트", target: "등", sets: 3, reps: 10, weight: "20kg", bpm: nil, rom: nil, training_type: :form_practice }
            ]
          },
          3 => {
            training_type: :sustainability,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 6, reps: 10, weight: "10회 가능한 칸", bpm: 30, rom: :full },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 6, reps: 10, weight: "10회 가능한 무게로", bpm: 30, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 6, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: 10, reps: 15, weight: nil, bpm: nil, rom: :full },
              { name: "데드리프트", target: "등", sets: 3, reps: 10, weight: "20kg", bpm: nil, rom: nil, training_type: :form_practice }
            ]
          },
          4 => {
            training_type: :strength,
            exercises: [
              { name: "푸시업", target: "가슴", sets: 5, reps: 10, weight: "10회 가능한 칸", bpm: nil, rom: :full },
              { name: "렛풀다운", target: "등", sets: 5, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "기둥 스쿼트", target: "하체", sets: 5, reps: 10, weight: nil, bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 150, weight: nil, bpm: nil, rom: :full, how_to: "150개 채우기" },
              { name: "데드리프트", target: "등", sets: 3, reps: 10, weight: "20kg", bpm: nil, rom: nil, training_type: :form_practice }
            ]
          },
          5 => {
            training_type: :cardiovascular,
            exercises: [
              { name: "타바타 푸시업", target: "가슴", sets: nil, reps: 150, weight: "10회 가능한 칸 + 2", bpm: nil, rom: :short, work_seconds: 20, how_to: "150개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 150, weight: "10회 가능한 무게로", bpm: nil, rom: :short, work_seconds: 20, how_to: "150개 채우기" },
              { name: "타바타 기둥 스쿼트", target: "하체", sets: nil, reps: 150, weight: nil, bpm: nil, rom: :short, work_seconds: 20, how_to: "150개 채우기" }
            ]
          }
        },
        3 => {
          1 => {
            training_type: :strength,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 5, reps: 15, weight: "15회 가능한 칸", bpm: 30, rom: :full },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 5, reps: 15, weight: nil, bpm: 30, rom: :full },
              { name: "스쿼트", target: "하체", sets: 5, reps: 15, weight: "30kg", bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 5, reps: 10, weight: "20kg", bpm: nil, rom: :full, training_type: :form_practice }
            ]
          },
          2 => {
            training_type: :muscular_endurance,
            exercises: [
              { name: "푸시업", target: "가슴", sets: nil, reps: 200, weight: "15회 가능한 칸 + 1", bpm: nil, rom: :short, how_to: "200개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :short, how_to: "200개 채우기" },
              { name: "스쿼트", target: "하체", sets: nil, reps: 200, weight: "20kg", bpm: nil, rom: :short, how_to: "200개 채우기" },
              { name: "복근", target: "복근", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: nil, reps: 100, weight: "20kg", bpm: nil, rom: :full, how_to: "100개 채우기", training_type: :form_practice }
            ]
          },
          3 => {
            training_type: :sustainability,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 7, reps: 10, weight: "10회 가능한 칸", bpm: 30, rom: :full },
              { name: "렛풀다운", target: "등", sets: 7, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 7, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: 10, reps: 10, weight: nil, bpm: nil, rom: :full },
              { name: "데드리프트", target: "등", sets: nil, reps: 150, weight: "20kg", bpm: nil, rom: :full, how_to: "150개 채우기", training_type: :form_practice }
            ]
          },
          4 => {
            training_type: :strength,
            exercises: [
              { name: "푸시업", target: "가슴", sets: 5, reps: 15, weight: "15회 가능한 칸", bpm: nil, rom: :full },
              { name: "렛풀다운", target: "등", sets: 5, reps: 15, weight: "15회 가능한 무게로", bpm: nil, rom: :full },
              { name: "스쿼트", target: "하체", sets: 5, reps: 20, weight: "20kg", bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 5, reps: 15, weight: "20kg", bpm: nil, rom: :full, training_type: :form_practice }
            ]
          },
          5 => {
            training_type: :cardiovascular,
            exercises: [
              { name: "타바타 푸시업", target: "가슴", sets: nil, reps: 200, weight: "10회 가능한 칸 + 2", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 200, weight: "10회 가능한 무게로", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 기둥 스쿼트", target: "하체", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" }
            ]
          }
        },
        4 => {
          1 => {
            training_type: :strength,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 5, reps: 20, weight: "20회 가능한 칸", bpm: 30, rom: :full },
              { name: "렛풀다운", target: "등", sets: 5, reps: 20, weight: nil, bpm: nil, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 10, reps: 20, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: 1, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 5, reps: 20, weight: "40kg", bpm: nil, rom: :full }
            ]
          },
          2 => {
            training_type: :muscular_endurance,
            exercises: [
              { name: "푸시업", target: "가슴", sets: 1, reps: 200, weight: "20회 가능한 칸 + 1", bpm: nil, rom: :short, how_to: "200개 채우기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: nil, bpm: nil, rom: :short, how_to: "200개 채우기" },
              { name: "기둥 스쿼트", target: "하체", sets: 1, reps: 200, weight: nil, bpm: nil, rom: :short, how_to: "200개 채우기" },
              { name: "복근", target: "복근", sets: 1, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 1, reps: 200, weight: "40kg", bpm: nil, rom: :full }
            ]
          },
          3 => {
            training_type: :strength,
            exercises: [
              { name: "푸시업", target: "가슴", sets: 5, reps: 20, weight: "20회 가능한 칸", bpm: nil, rom: :full },
              { name: "렛풀다운", target: "등", sets: 5, reps: 20, weight: "20회 가능한 무게로", bpm: nil, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 5, reps: 20, weight: nil, bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: 1, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 5, reps: 15, weight: "40kg", bpm: nil, rom: :full }
            ]
          },
          4 => {
            training_type: :sustainability,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 7, reps: 10, weight: "10회 가능한 무게로", bpm: 30, rom: :full },
              { name: "렛풀다운", target: "등", sets: 7, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 7, reps: 10, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: 10, reps: 20, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 7, reps: 10, weight: "40kg", bpm: nil, rom: :full }
            ]
          },
          5 => {
            training_type: :cardiovascular,
            exercises: [
              { name: "타바타 푸시업", target: "가슴", sets: 1, reps: 200, weight: "10회 가능한 칸 + 2", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: "10회 가능한 무게로", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 기둥 스쿼트", target: "하체", sets: 1, reps: 200, weight: nil, bpm: nil, rom: :full, work_seconds: 20, how_to: "200개 채우기" }
            ]
          }
        }
      },
      promotion_test: {
        exercises: [
          { name: "푸시업 (BPM 1칸)", target_reps: 20 },
          { name: "스쿼트 (BPM; 키-100kg)", target_reps: 10 },
          { name: "로잉 (1km)", target_time: "04:00" },
          { name: "체지방율", target: "18% 이하" }
        ]
      }
    }.freeze

    # ============================================================
    # INTERMEDIATE PROGRAM (중급) - 1 week repeating
    # Source: 운동프로그램[중급].xlsx
    # ============================================================
    INTERMEDIATE = {
      level: "intermediate",
      korean: "중급",
      numeric_levels: [3, 4, 5],
      weeks: 1, # repeating week
      program: {
        1 => {
          1 => { # 월요일 - 근력+순발력
            training_type: :strength_power,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: nil, reps: 10, weight: "20kg부터 10회 가능한 무게를 계속 증량", bpm: nil, rom: :full, how_to: "점진적 증량 후 드랍세트" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 10, weight: "20kg부터 10회 가능한 무게를 계속 증량", bpm: nil, rom: :full },
              { name: "스쿼트", target: "하체", sets: nil, reps: 10, weight: "20kg부터 10회 가능한 무게를 계속 증량", bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "랙풀 데드리프트", target: "등", sets: nil, reps: 10, weight: "20kg부터 10회 가능한 무게를 계속 증량", bpm: nil, rom: :full },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full, how_to: "프론트, 사이드, 리어 순서로 이어서 수행, 총 3세트" }
            ],
            purpose: "근력 + 순발력 훈련: 20kg부터 시작해서 10회 가능한 무게까지 계속 증량"
          },
          2 => { # 화요일 - 근지구력
            training_type: :muscular_endurance,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: nil, reps: 200, weight: "최대 중량 x 0.8", bpm: nil, rom: :medium, how_to: "200개 채우기" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 200, weight: "최대 중량 x 0.8", bpm: nil, rom: :medium, how_to: "200개 채우기" },
              { name: "벤치 스쿼트", target: "하체", sets: nil, reps: 200, weight: "최대 중량 x 0.8", bpm: nil, rom: :medium, how_to: "200개 채우기" },
              { name: "복근", target: "복근", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "루마니안 데드리프트", target: "등", sets: nil, reps: 200, weight: "최대 중량 x 0.8", bpm: nil, rom: :medium, how_to: "200개 채우기" },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full }
            ]
          },
          3 => { # 수요일 - 근지구력 (100회 도전)
            training_type: :muscular_endurance,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full, how_to: "100회 가능한 칸 도전 후 실패시 해당 칸에서 + 4세트" },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full, how_to: "가동범위 최대, BPM 무관" },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full, how_to: "가동범위 최대, BPM 무관" },
              { name: "복근", target: "복근", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, how_to: "200개 채우기" },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full }
            ]
          },
          4 => { # 목요일 - 지속력
            training_type: :sustainability,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 5, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "렛풀다운", target: "등", sets: 5, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "스쿼트", target: "하체", sets: 5, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: 10, reps: 20, weight: nil, bpm: nil, rom: :full },
              { name: "데드리프트", target: "등", sets: 5, reps: 10, weight: "10회 가능한 무게로", bpm: nil, rom: nil },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full }
            ],
            purpose: "각 세트에서 10개를 몇 세트까지 지속할 수 있는지 확인"
          },
          5 => { # 금요일 - 심폐지구력
            training_type: :cardiovascular,
            exercises: [
              { name: "타바타 벤치프레스", target: "가슴", sets: nil, reps: 200, weight: "최대 중량 x 0.4", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 렛풀다운", target: "등", sets: nil, reps: 200, weight: "최대 중량 x 0.4", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 기둥 스쿼트", target: "하체", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 인력거", target: "어깨", sets: 20, reps: nil, weight: "자유", bpm: nil, rom: :full, work_seconds: 20, how_to: "20세트" }
            ],
            purpose: "20초 운동 + 10초 휴식, 운동 시간 동안 최대한의 힘을 쏟아내는 것이 중요"
          }
        }
      },
      promotion_test: {
        exercises: [
          { name: "벤치프레스 1RM", target: "체중 x 1.0" },
          { name: "스쿼트 1RM", target: "체중 x 1.2" },
          { name: "데드리프트 1RM", target: "체중 x 1.4" }
        ]
      }
    }.freeze

    # ============================================================
    # ADVANCED PROGRAM (고급) - 1 week repeating + 돌파 전략
    # Source: 운동프로그램[고급].xlsx
    # ============================================================
    ADVANCED = {
      level: "advanced",
      korean: "고급",
      numeric_levels: [6, 7, 8],
      weeks: 1,
      program: {
        1 => {
          1 => { # 월요일 - 근력+순발력 (드랍세트)
            training_type: :strength_power,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: nil, reps: 10, weight: nil, bpm: nil, rom: :full,
                how_to: "20kg부터 10회 가능한 무게를 계속 증량. 10회 실패 시점부터 -10kg씩 무게 내리며 가동범위 깔짝으로, 100회 가능한 무게까지 지속" },
              { name: "렛풀다운", target: "등", sets: nil, reps: 10, weight: nil, bpm: nil, rom: :full,
                how_to: "20kg부터 10회 가능한 무게를 계속 증량 후 드랍" },
              { name: "스쿼트", target: "하체", sets: nil, reps: 10, weight: nil, bpm: nil, rom: :full,
                how_to: "20kg부터 10회 가능한 무게를 계속 증량 후 드랍" },
              { name: "복근", target: "복근", sets: 5, reps: 100, weight: "칸별 복근", bpm: nil, rom: :full, how_to: "칸별 복근 100회씩 채우기" },
              { name: "랙풀 데드리프트", target: "등", sets: nil, reps: 10, weight: nil, bpm: nil, rom: :full,
                how_to: "20kg부터 10회 가능한 무게를 계속 증량 후 드랍" },
              { name: "시티드 덤벨 프레스", target: "어깨", sets: nil, reps: 10, weight: nil, bpm: nil, rom: :full,
                how_to: "점진적 증량 후 드랍" },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full }
            ],
            purpose: "근력 + 순발력 훈련: 드랍세트 방식"
          },
          2 => { # 화요일 - 근지구력 (드랍세트 3,6,9)
            training_type: :dropset,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 3, reps: "30,60,90", weight: "최대 중량 x 0.8부터", bpm: nil, rom: :medium,
                how_to: "드랍세트(3,6,9): 30개 60개 90개를 트레이너의 보조를 받아 수행, 각 세트는 이어서 수행" },
              { name: "렛풀다운", target: "등", sets: 3, reps: "30,60,90", weight: "최대 중량 x 0.8부터", bpm: nil, rom: :medium, how_to: "드랍세트(3,6,9)" },
              { name: "벤치 스쿼트", target: "하체", sets: 3, reps: "30,60,90", weight: "최대 중량 x 0.8부터", bpm: nil, rom: :medium, how_to: "드랍세트(3,6,9)" },
              { name: "루마니안 데드리프트", target: "등", sets: 3, reps: "30,60,90", weight: "최대 중량 x 0.8부터", bpm: nil, rom: :full, how_to: "드랍세트(3,6,9)" },
              { name: "숄더 프레스 머신", target: "어깨", sets: 3, reps: "30,60,90", weight: "최대 중량 x 0.8부터", bpm: nil, rom: :medium, how_to: "드랍세트(3,6,9)" },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full },
              { name: "복근", target: "복근", sets: 5, reps: 100, weight: "칸별 복근", bpm: nil, rom: :full, how_to: "칸별 복근 100회씩 채우기" }
            ]
          },
          3 => { # 수요일 - 근지구력 (100회 도전)
            training_type: :muscular_endurance,
            exercises: [
              { name: "BPM 푸시업", target: "가슴", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full },
              { name: "BPM 9칸 턱걸이", target: "등", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full },
              { name: "BPM 기둥 스쿼트", target: "하체", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: 5, reps: 100, weight: "칸별 복근", bpm: nil, rom: :full, how_to: "칸별 복근 100회씩 채우기" },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full },
              { name: "트랩바/루마니안 데드리프트", target: "등", sets: 1, reps: 100, weight: "100회 도전!", bpm: nil, rom: :full }
            ]
          },
          4 => { # 목요일 - 지속력
            training_type: :sustainability,
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: nil, reps: 20, weight: "20회 가능한 무게로", bpm: nil, rom: :full },
              { name: "렛풀다운", target: "등", sets: nil, reps: 20, weight: "20회 가능한 무게로", bpm: nil, rom: :full },
              { name: "스쿼트", target: "하체", sets: nil, reps: 20, weight: "20회 가능한 무게로", bpm: nil, rom: :full },
              { name: "복근", target: "복근", sets: 5, reps: 100, weight: "칸별 복근", bpm: nil, rom: :full, how_to: "칸별 복근 100회씩 채우기" },
              { name: "시티드 덤벨 프레스", target: "어깨", sets: nil, reps: 20, weight: "20회 가능한 무게로", bpm: nil, rom: :full },
              { name: "루마니안 데드리프트", target: "등", sets: nil, reps: 20, weight: "20회 가능한 무게로", bpm: nil, rom: nil },
              { name: "레이즈 3종", target: "어깨", sets: 3, reps: 30, weight: nil, bpm: 30, rom: :full }
            ],
            purpose: "각 세트에서 10개를 몇 세트까지 지속할 수 있는지 확인"
          },
          5 => { # 금요일 - 심폐지구력
            training_type: :cardiovascular,
            exercises: [
              { name: "타바타 벤치프레스", target: "가슴", sets: nil, reps: 200, weight: "최대 중량 x 0.4", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 렛풀다운", target: "등", sets: nil, reps: 200, weight: "최대 중량 x 0.4", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 머신 데드리프트", target: "등", sets: nil, reps: 200, weight: "최대 중량 x 0.4", bpm: nil, rom: :short, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 발박수", target: "하체", sets: nil, reps: 200, weight: nil, bpm: nil, rom: :full, work_seconds: 20, how_to: "200개 채우기" },
              { name: "타바타 원판 인력거", target: "어깨", sets: 30, reps: nil, weight: "자유", bpm: nil, rom: :short, work_seconds: 20, how_to: "30세트" },
              { name: "타바타 복근", target: "복근", sets: nil, reps: 300, weight: nil, bpm: nil, rom: :short, work_seconds: 20, how_to: "300개 채우기" }
            ],
            purpose: "20초 운동 + 10초 휴식, 운동 시간 동안 최대한의 힘을 쏟아내는 것이 중요"
          }
        }
      },
      breakthrough_strategies: {
        weight_breakthrough: {
          name: "중량 돌파",
          how_to: "풀 반복 2회 가능한 최대 중량으로 100세트",
          description: "최고 중량 갱신을 위한 전략"
        },
        reps_breakthrough: {
          name: "반복 횟수 돌파",
          how_to: "최대 중량 x 0.4로 1000개 채우기",
          description: "지구력 향상을 위한 전략"
        },
        fat_burning: {
          name: "지방 연소",
          how_to: "타바타 인터벌 최소 20세트 이상",
          description: "체지방 감소를 위한 전략"
        }
      }
    }.freeze

    # ============================================================
    # SHIMHYUNDO ROUTINE (심현도 무분할 루틴) - 8 levels
    # Source: 심현도_무분할 루틴.xlsx
    # ============================================================
    SHIMHYUNDO = {
      name: "심현도 무분할 루틴",
      type: "full_body",
      levels: 8,
      days_per_week: 6, # 월~토
      weight_standards: {
        bench_press: { base: "키 - 100", level_multiplier: [1, 1.14, 1.28, 1.42, 1.56, 1.7] },
        squat: { base: "(키 - 100) + 20", level_multiplier: [1, 1.14, 1.28, 1.42, 1.56, 1.7] },
        deadlift: { base: "(키 - 100) + 40", level_multiplier: [1, 1.14, 1.28, 1.42, 1.56, 1.7] }
      },
      program: {
        1 => { # LEVEL 1
          1 => { # 월요일
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: "max", weight: "1~5칸", how_to: "칸별 100개 되면 종료" },
              { name: "9칸 턱걸이", target: "등", sets: nil, reps: 100, weight: nil, how_to: "100개 채우기" },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 100, weight: nil, how_to: "100개 채우기" },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "1kg", how_to: "사이드, 프론트, 리어 순서로 이어서 수행, 총 5세트" },
              { name: "2분 싯업", target: "복근", sets: 3, reps: nil, weight: nil, how_to: "2분간 수행" }
            ]
          },
          2 => { # 화요일
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 5, reps: 20, weight: "20회 가능한 위치", how_to: "20회 가능한 위치에서 수행" },
              { name: "렛풀다운", target: "등", sets: 5, reps: 20, weight: "20회 가능한 무게", how_to: "20회 가능한 무게로 수행" },
              { name: "볼스쿼트", target: "하체", sets: nil, reps: 200, weight: "맨몸", how_to: "200개 채우기" },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "1kg" },
              { name: "윗몸", target: "복근", sets: 1, reps: 150, weight: nil, how_to: "150개 채우기" }
            ]
          },
          3 => { # 수요일
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: 200, weight: "3칸", how_to: "200개 채우기" },
              { name: "캐틀벨 스윙", target: "등", sets: 1, reps: 200, weight: "10kg", how_to: "200개 채우기" },
              { name: "9칸 턱걸이", target: "등", sets: nil, reps: 100, weight: nil, how_to: "100개 채우기" },
              { name: "윗몸", target: "복근", sets: 1, reps: 150, weight: nil, how_to: "150개 채우기" }
            ]
          },
          4 => { # 목요일
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 10, reps: "max", weight: nil, how_to: "10세트" },
              { name: "9칸 턱걸이", target: "등", sets: 10, reps: "max", weight: nil, how_to: "10세트" },
              { name: "기둥스쿼트", target: "하체", sets: 10, reps: "max", weight: nil, how_to: "10세트" },
              { name: "윗몸", target: "복근", sets: 1, reps: 150, weight: nil, how_to: "150개 채우기" }
            ]
          },
          5 => { # 금요일
            exercises: [
              { name: "Push-up", target: "가슴", sets: 1, reps: 200, weight: nil, how_to: "타바타로 200개 채우기" },
              { name: "9칸 턱걸이", target: "등", sets: 1, reps: 200, weight: nil, how_to: "타바타로 200개 채우기" },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 200, weight: nil, how_to: "타바타로 200개 채우기" }
            ]
          },
          6 => { # 토요일 - 자율
            exercises: [
              { name: "자율", target: "전체", sets: nil, reps: nil, weight: nil, how_to: "자율 운동" }
            ]
          }
        },
        2 => { # LEVEL 2
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: "max", reps: "max", weight: "10회 가능하면 계속 증량", how_to: "10회 가능하면 계속 증량" },
              { name: "9칸 턱걸이", target: "등", sets: 5, reps: 20, weight: nil, how_to: "20개씩 5세트" },
              { name: "데드리프트", target: "등", sets: 5, reps: 30, weight: "20kg", how_to: nil },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: 30, weight: nil, how_to: nil },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 5, reps: "max", weight: "20회 가능한 무게", how_to: "20회 가능한 무게로 수행" },
              { name: "렛풀다운", target: "등", sets: 5, reps: "max", weight: "20kg", how_to: nil },
              { name: "볼스쿼트", target: "하체", sets: 5, reps: "max", weight: "20kg", how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: "사이드, 프론트, 리어 순서로 이어서 수행" },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: "max", weight: "1~5칸", how_to: "칸별 100개 되면 종료" },
              { name: "데드리프트", target: "등", sets: 5, reps: 12, weight: "20kg", how_to: nil },
              { name: "스쿼트", target: "하체", sets: 10, reps: "max", weight: "max", how_to: "10세트 수행하기" },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          4 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 3, reps: "10,20", weight: "1칸,2칸", how_to: "빙고로 3세트 수행" },
              { name: "9칸 턱걸이", target: "등", sets: 5, reps: 20, weight: nil, how_to: "20개씩 5세트" },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: 30, weight: nil, how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "바벨컬", target: "이두", sets: 5, reps: 20, weight: "10kg", how_to: nil },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          },
          5 => {
            exercises: [
              { name: "푸시업", target: "가슴", sets: 1, reps: 200, weight: nil, how_to: "타바타로 200개 채우기" },
              { name: "9칸 턱걸이", target: "등", sets: 1, reps: 200, weight: nil, how_to: "타바타로 200개 채우기" },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 200, weight: nil, how_to: nil },
              { name: "프레스+레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: "사이드, 프론트, 리어 순서로 이어서 수행" },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          6 => { exercises: [{ name: "자율", target: "전체", sets: nil, reps: nil, weight: nil, how_to: "자율 운동" }] }
        },
        3 => { # LEVEL 3
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: "max", reps: "max", weight: "10회 가능하면 계속 증량", how_to: "10회 가능하면 계속 증량" },
              { name: "데드리프트", target: "등", sets: 5, reps: 30, weight: "20kg", how_to: nil },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: 30, weight: nil, how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "바벨컬", target: "이두", sets: 5, reps: 20, weight: "10kg", how_to: nil },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 5, reps: "max", weight: "20회 가능한 무게", how_to: "20회 가능한 무게로 수행" },
              { name: "렛풀다운", target: "등", sets: 5, reps: "max", weight: "20kg", how_to: nil },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 200, weight: nil, how_to: "200개 채우기" },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "라잉트라이셉스", target: "삼두", sets: 5, reps: 20, weight: "20kg", how_to: nil },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: "max", weight: "1~5칸", how_to: "칸별 100개 되면 종료" },
              { name: "데드리프트", target: "등", sets: 5, reps: 12, weight: "40kg", how_to: nil },
              { name: "스쿼트", target: "하체", sets: 10, reps: "max", weight: "max", how_to: "10세트 수행하기" },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          4 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 3, reps: "10,20", weight: "max, max-20", how_to: "빙고로 3세트 수행" },
              { name: "9칸 턱걸이", target: "등", sets: 5, reps: 20, weight: nil, how_to: "20개씩 5세트" },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: 30, weight: nil, how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          },
          5 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "max - 20", how_to: "타바타로 200개 채우기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: "max - 20", how_to: "타바타로 200개 채우기" },
              { name: "발박수", target: "하체", sets: 1, reps: 200, weight: nil, how_to: "타바타로 200개 채우기" },
              { name: "프레스+레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: nil },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          6 => { exercises: [{ name: "자율", target: "전체", sets: nil, reps: nil, weight: nil, how_to: "자율 운동" }] }
        },
        4 => { # LEVEL 4
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: "max", reps: "max", weight: "10회 가능하면 계속 증량", how_to: "10회 가능하면 계속 증량" },
              { name: "9칸 턱걸이", target: "등", sets: 5, reps: 20, weight: nil, how_to: "20개씩 5세트" },
              { name: "데드리프트", target: "등", sets: 5, reps: 30, weight: "20kg", how_to: nil },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: 30, weight: nil, how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "바벨컬", target: "이두", sets: 5, reps: 20, weight: "10kg", how_to: nil },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 5, reps: "max", weight: "20회 가능한 무게", how_to: "20회 가능한 무게로 수행" },
              { name: "렛풀다운", target: "등", sets: 5, reps: "max", weight: "20kg", how_to: nil },
              { name: "볼스쿼트", target: "하체", sets: 5, reps: "max", weight: "50kg", how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "라잉트라이셉스", target: "삼두", sets: 5, reps: 20, weight: "20kg", how_to: nil },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: "max", weight: "1~5칸", how_to: "칸별 100개 되면 종료" },
              { name: "데드리프트", target: "등", sets: 5, reps: 12, weight: "40kg", how_to: nil },
              { name: "스쿼트", target: "하체", sets: 10, reps: "max", weight: "max", how_to: "10세트 수행하기" },
              { name: "인력거", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          4 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 3, reps: "10,20", weight: "max, max-20", how_to: "빙고로 3세트 수행" },
              { name: "9칸 턱걸이", target: "등", sets: 5, reps: 20, weight: nil, how_to: "20개씩 5세트" },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: 30, weight: nil, how_to: nil },
              { name: "레이즈 3종세트", target: "어깨", sets: 3, reps: 30, weight: "3kg", how_to: nil },
              { name: "인력거", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "바벨컬", target: "이두", sets: 5, reps: 20, weight: "10kg", how_to: nil },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          },
          5 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "프레스+레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: nil },
              { name: "인력거", target: "어깨", sets: 20, reps: "max", weight: "10kg 원판", how_to: "10키로 원판 인력거 20세트" },
              { name: "2분 싯업", target: "복근", sets: 1, reps: nil, weight: nil, how_to: nil }
            ]
          },
          6 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 5, reps: "max", weight: "max - 20", how_to: nil },
              { name: "턱걸이", target: "등", sets: 5, reps: "max", weight: nil, how_to: "max 5세트" },
              { name: "인력거", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "라잉트라이셉스", target: "삼두", sets: 5, reps: 20, weight: "20kg", how_to: nil },
              { name: "윗몸", target: "복근", sets: 1, reps: 200, weight: nil, how_to: nil }
            ]
          }
        },
        5 => { # LEVEL 5
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: "max", reps: "max", weight: "10회 가능하면 계속 증량", how_to: "10회 가능하면 계속 증량" },
              { name: "9칸 턱걸이", target: "등", sets: 1, reps: 200, weight: nil, how_to: "200개 채우기" },
              { name: "스쿼트", target: "하체", sets: 1, reps: 200, weight: "40kg", how_to: "200개 채우기" },
              { name: "프레스+레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: nil }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "max - 20", how_to: "200개 채우기" },
              { name: "데드리프트", target: "등", sets: 10, reps: "max", weight: "max", how_to: "6칸 데드, 10회 가능하면 계속 증량" },
              { name: "기둥스쿼트", target: "하체", sets: 5, reps: "max", weight: nil, how_to: nil },
              { name: "잠머/인력거/딥스/사이드레이즈", target: "어깨", sets: 5, reps: 30, weight: "10/30/60/3", how_to: "각각의 종목을 모두 수행하면 1세트" }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 5, reps: "max", weight: "1칸", how_to: "1칸 max 5세트" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: "max - 30", how_to: "200개 채우기" },
              { name: "스쿼트", target: "하체", sets: 10, reps: "max", weight: "max", how_to: "10세트 수행하기" },
              { name: "BPM 7분 레이즈 3종", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "7분 동안 수행" },
              { name: "인력거", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" }
            ]
          },
          4 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 3, reps: "10,20", weight: "max, max-20", how_to: "빙고로 3세트 수행" },
              { name: "렛풀다운", target: "등", sets: 5, reps: "max", weight: "max", how_to: "max" },
              { name: "9칸 턱걸이", target: "등", sets: 1, reps: 100, weight: nil, how_to: "100개 채우기" },
              { name: "스쿼트", target: "하체", sets: 8, reps: 8, weight: "80kg", how_to: nil },
              { name: "핸드프레스", target: "어깨", sets: 5, reps: "max", weight: "10kg", how_to: "5세트 수행하기" }
            ]
          },
          5 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "잠머", target: "어깨", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "인력거", target: "어깨", sets: 20, reps: "max", weight: "10kg 원판", how_to: "10키로 원판 인력거 20세트" }
            ]
          },
          6 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 10, reps: "max", weight: "max", how_to: "10세트 수행하기" },
              { name: "턱걸이", target: "등", sets: 8, reps: "max", weight: nil, how_to: "max 8세트" },
              { name: "인력거", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" }
            ]
          }
        },
        6 => { # LEVEL 6
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 10, reps: "max", weight: "max", how_to: "10세트 수행하기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "스쿼트", target: "하체", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "Jammer", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: nil }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 100, weight: "max", how_to: "100개 채우기" },
              { name: "데드리프트", target: "등", sets: 10, reps: "max", weight: "max", how_to: "6칸 데드, 10회 가능하면 계속 증량" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 100, weight: "max", how_to: "100개 채우기" },
              { name: "박스쿼트", target: "하체", sets: 1, reps: 300, weight: "40kg", how_to: "300개 채우기" },
              { name: "인력거", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 5, reps: "max", weight: "1칸", how_to: "1칸 max 5세트" },
              { name: "암풀다운", target: "등", sets: 5, reps: 30, weight: "30kg", how_to: "5세트 채우기" },
              { name: "트랩바", target: "등", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 무게로 계속 증량하기" },
              { name: "BPM 10분 레이즈 3종", target: "어깨", sets: 1, reps: "max", weight: "max", how_to: "10분 동안 수행" }
            ]
          },
          4 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 3, reps: "10,20,40", weight: "max, max-20, max-40", how_to: "빙고로 3세트 수행" },
              { name: "턱걸이", target: "등", sets: 5, reps: "max", weight: nil, how_to: "max" },
              { name: "9칸 턱걸이", target: "등", sets: 1, reps: 100, weight: nil, how_to: "100개 채우기" },
              { name: "루마니안 데드리프트", target: "등", sets: 5, reps: "max", weight: "80kg", how_to: "max로 5세트 수행" },
              { name: "볼스쿼트", target: "하체", sets: 5, reps: "10,20,30,40", weight: "100/80/60/40", how_to: nil },
              { name: "핸드프레스", target: "어깨", sets: nil, reps: 30, weight: "10~1kg", how_to: "각 1세트씩 무게 감량하면서 수행" }
            ]
          },
          5 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "기둥스쿼트", target: "하체", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "잠머", target: "어깨", sets: 1, reps: 200, weight: "max", how_to: "타바타로 200개 채우기" },
              { name: "인력거", target: "어깨", sets: 20, reps: "max", weight: "10kg 원판", how_to: "10키로 원판 인력거 20세트" }
            ]
          },
          6 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 300, weight: "50kg", how_to: "300개 부분반복으로 채우기" }
            ]
          }
        },
        7 => { # LEVEL 7
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 최대무게에서 50회 가능한 무게까지 10kg씩 내려오기" },
              { name: "렛풀다운", target: "등", sets: 1, reps: "max", weight: "max", how_to: "10회 가능한 최대무게에서 100회 가능한 무게까지 10kg씩 내려오기" },
              { name: "Jammer", target: "어깨", sets: 1, reps: 300, weight: "20kg", how_to: "300개 채우기" }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 100, weight: "max", how_to: "100개 채우기" },
              { name: "스쿼트", target: "하체", sets: 1, reps: 100, weight: "max", how_to: "100개 채우기" },
              { name: "인력거", target: "어깨", sets: 1, reps: 300, weight: "40kg", how_to: "300개 채우기" }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: 200, weight: "1칸", how_to: "1칸 200개 채우기" },
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "40kg", how_to: "200개 채우기" },
              { name: "BPM Shoulder press", target: "어깨", sets: 1, reps: 300, weight: "max", how_to: "300개 채우기" },
              { name: "레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: nil }
            ]
          },
          4 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 10, reps: 60, weight: "50kg", how_to: "600개 채우기" }
            ]
          },
          5 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "60kg", how_to: "타바타로 200개 채우기" }
            ]
          },
          6 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 500, weight: "50kg", how_to: "500개 부분반복으로 수행하기" }
            ]
          }
        },
        8 => { # LEVEL 8 - 최고 레벨
          1 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: "max", weight: "120/110/100/90/80/70", how_to: "각 1세트 max rep로 수행" },
              { name: "루마니안 데드리프트", target: "등", sets: 5, reps: "max", weight: "180kg", how_to: "5세트 max reps로 수행" },
              { name: "렛풀다운", target: "등", sets: 5, reps: "max", weight: "60kg", how_to: "5세트 max reps로 수행" },
              { name: "스쿼트", target: "하체", sets: 10, reps: 3, weight: "100kg", how_to: "3, 6, 9 수행하기" },
              { name: "Jammer", target: "어깨", sets: 5, reps: 30, weight: "40kg", how_to: "Jammer로 5세트 수행" },
              { name: "인클라인 프레스", target: "어깨", sets: 1, reps: 200, weight: "50kg", how_to: "200개 채우기" },
              { name: "바벨컬", target: "이두", sets: 5, reps: 20, weight: "30kg", how_to: "수퍼세트로 수행" },
              { name: "라잉트라이셉", target: "삼두", sets: 5, reps: 20, weight: "50kg", how_to: nil },
              { name: "옥상", target: "복근", sets: 5, reps: "max", weight: "5kg", how_to: "max로 5세트 수행하기" }
            ]
          },
          2 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 100, weight: "100kg", how_to: "100개 채우기" },
              { name: "턱걸이", target: "등", sets: 10, reps: "max", weight: nil, how_to: "10세트 max reps로 수행" },
              { name: "암풀다운", target: "등", sets: 5, reps: "max", weight: "40kg", how_to: "5세트 max reps로 수행" },
              { name: "스쿼트", target: "하체", sets: 1, reps: "max", weight: "180/160/140/100", how_to: "각 무게 별로 max reps로 수행" },
              { name: "레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: "사이드, 프론트, 리어 순서로 이어서 수행" },
              { name: "인력거", target: "어깨", sets: "max", reps: 10, weight: "max", how_to: "10회 가능하면 증량, 실패 후 내려오면서 조지기" },
              { name: "덤벨컬", target: "이두", sets: 1, reps: 200, weight: "8kg", how_to: "200개 채우기" },
              { name: "푸시다운", target: "삼두", sets: 1, reps: 200, weight: "50kg", how_to: "200개 채우기" },
              { name: "mat 복근", target: "복근", sets: nil, reps: nil, weight: nil, how_to: nil }
            ]
          },
          3 => {
            exercises: [
              { name: "BPM Pushup", target: "가슴", sets: 1, reps: "max", weight: "1~5칸", how_to: "칸별 100개 되면 종료" },
              { name: "트랩바", target: "등", sets: 5, reps: "max", weight: "220kg", how_to: "5세트 max 횟수로 5세트 수행" },
              { name: "BPM 새우", target: "하체", sets: 5, reps: "max", weight: nil, how_to: "BPM 새우 5세트 수행" },
              { name: "레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: nil },
              { name: "BPM press", target: "어깨", sets: 3, reps: 100, weight: nil, how_to: "100회 가능한 무게로 3세트 수행하기" },
              { name: "옥상", target: "복근", sets: 1, reps: "max", weight: nil, how_to: nil }
            ]
          },
          4 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 3, reps: "10,20,30,40", weight: "100/80/60/40", how_to: "100부터 40까지 이어서 reps를 수행하고 이를 3세트 반복한다" },
              { name: "턱걸이", target: "등", sets: 10, reps: "max", weight: nil, how_to: "6칸 데드, 10회 가능하면 계속 증량" },
              { name: "바벨로우", target: "등", sets: 3, reps: "10,20,30", weight: "100/80/60", how_to: "빙고 3세트 수행" },
              { name: "박스스쿼트", target: "하체", sets: 1, reps: 200, weight: "100kg", how_to: "200개 채우기" },
              { name: "핸드프레스", target: "어깨", sets: 1, reps: 300, weight: "8kg", how_to: "8kg 300개 채우기" },
              { name: "잠머/인력거/딥스/사이드레이즈", target: "어깨", sets: 5, reps: 30, weight: "10/30/60/3", how_to: "각각의 종목을 모두 수행하면 1세트로 하고 레이즈는 BPM으로 수행한다" },
              { name: "2분 싯업", target: "복근", sets: 5, reps: nil, weight: nil, how_to: nil }
            ]
          },
          5 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 200, weight: "60kg", how_to: "타바타로 200개 채우기" },
              { name: "밴드 턱걸이 타바타", target: "등", sets: 1, reps: 200, weight: "난이도는 밴드로 조절", how_to: "타바타로 200개 채우기" },
              { name: "암풀다운", target: "등", sets: 1, reps: 300, weight: nil, how_to: "타바타로 300개 채우기" },
              { name: "발박수 타바타", target: "하체", sets: 1, reps: 300, weight: nil, how_to: "타바타로 300개 채우기" },
              { name: "인력거", target: "어깨", sets: 50, reps: "max", weight: "10kg 원판", how_to: "타바타로 원판을 들고 인력거를 수행한다" }
            ]
          },
          6 => {
            exercises: [
              { name: "벤치프레스", target: "가슴", sets: 1, reps: 300, weight: "60kg", how_to: "300개 채우기" },
              { name: "바벨로우", target: "등", sets: 1, reps: 200, weight: "60kg", how_to: "바벨로우 200개 채우기" },
              { name: "볼스쿼트", target: "하체", sets: 1, reps: 1000, weight: "60kg", how_to: "볼스쿼트 60kg 1000개 채우기" },
              { name: "레이즈 3종세트", target: "어깨", sets: 5, reps: 30, weight: "3kg", how_to: "사이드, 프론트, 리어 순서로 이어서 수행하고 총 5세트" }
            ]
          }
        }
      }
    }.freeze

    # ============================================================
    # KIM SUNGHWAN ROUTINE (김성환님 운동루틴) - Phase-based
    # Source: 김성환님 운동루틴.xlsx
    # ============================================================
    KIMSUNGHWAN = {
      name: "김성환 운동 루틴",
      total_weeks: 15,
      phases: {
        beginner_prep: {
          name: "초급자 준비단계",
          duration: "2주",
          frequency: "주 4회",
          focus: "기초공사",
          exercises: [
            { name: "고관절 가동성", target: "하체" },
            { name: "견갑골 움직임", target: "상체" },
            { name: "코어 안정성", target: "코어" },
            { name: "유산소 (걷기/조깅)", target: "심폐" }
          ]
        },
        beginner: {
          name: "초급자",
          duration: "1개월",
          frequency: "주 5회",
          type: "무분할",
          exercises: [
            { name: "수직 당기기 (풀다운/턱걸이)", target: "등", sets: 3, reps: 10 },
            { name: "수평 당기기 (로우)", target: "등", sets: 3, reps: 10 },
            { name: "수직 밀기 (숄더프레스)", target: "어깨", sets: 3, reps: 10 },
            { name: "수평 밀기 (벤치프레스/푸시업)", target: "가슴", sets: 3, reps: 10 },
            { name: "데드리프트", target: "후면 사슬", sets: 3, reps: 10 },
            { name: "레그프레스/스쿼트", target: "하체", sets: 3, reps: 10 }
          ]
        },
        intermediate: {
          name: "중급자",
          duration: "6주 + 1주 디로딩 + 5주 + 2주 + 1주 디로딩",
          phases: {
            four_split: {
              name: "4분할",
              duration: "6주",
              schedule: {
                day1: {
                  target: "등/승모근",
                  exercises: [
                    { name: "랫풀다운", sets: 4, reps: 12 },
                    { name: "시티드 케이블 로우", sets: 4, reps: 12 },
                    { name: "원암 덤벨 로우", sets: 3, reps: 10 },
                    { name: "페이스 풀", sets: 3, reps: 15 },
                    { name: "바벨 쉬러그", sets: 4, reps: 12 }
                  ]
                },
                day2: {
                  target: "가슴/이두",
                  exercises: [
                    { name: "벤치프레스", sets: 4, reps: 10 },
                    { name: "인클라인 덤벨 프레스", sets: 4, reps: 12 },
                    { name: "케이블 크로스오버", sets: 3, reps: 15 },
                    { name: "바벨 컬", sets: 3, reps: 10 },
                    { name: "인클라인 덤벨 컬", sets: 3, reps: 12 }
                  ]
                },
                day3: {
                  target: "하체",
                  exercises: [
                    { name: "스쿼트", sets: 4, reps: 10 },
                    { name: "레그프레스", sets: 4, reps: 12 },
                    { name: "루마니안 데드리프트", sets: 3, reps: 10 },
                    { name: "레그 컬", sets: 3, reps: 12 },
                    { name: "카프 레이즈", sets: 4, reps: 15 }
                  ]
                },
                day4: {
                  target: "어깨/삼두/복부",
                  exercises: [
                    { name: "오버헤드 프레스", sets: 4, reps: 10 },
                    { name: "사이드 레터럴 레이즈", sets: 4, reps: 15 },
                    { name: "리어 델트 플라이", sets: 3, reps: 15 },
                    { name: "트라이셉스 푸시다운", sets: 3, reps: 12 },
                    { name: "오버헤드 트라이셉스 익스텐션", sets: 3, reps: 12 },
                    { name: "크런치", sets: 3, reps: 20 },
                    { name: "행잉 레그 레이즈", sets: 3, reps: 15 }
                  ]
                }
              }
            },
            deloading_1: {
              name: "디로딩",
              duration: "1주",
              description: "볼륨과 강도 50% 감소"
            },
            five_split: {
              name: "5분할",
              duration: "5주",
              schedule: {
                day1: {
                  target: "등",
                  exercises: [
                    { name: "풀업", sets: 4, reps: "max" },
                    { name: "바벨 로우", sets: 4, reps: 10 },
                    { name: "T바 로우", sets: 3, reps: 12 },
                    { name: "스트레이트 암 풀다운", sets: 3, reps: 15 },
                    { name: "덤벨 쉬러그", sets: 4, reps: 12 }
                  ]
                },
                day2: {
                  target: "가슴/복부",
                  exercises: [
                    { name: "인클라인 벤치프레스", sets: 4, reps: 10 },
                    { name: "덤벨 프레스", sets: 4, reps: 12 },
                    { name: "케이블 플라이", sets: 3, reps: 15 },
                    { name: "딥스", sets: 3, reps: 12 },
                    { name: "플랭크", sets: 3, reps: "60초" },
                    { name: "러시안 트위스트", sets: 3, reps: 20 }
                  ]
                },
                day3: {
                  target: "하체 옵션A (대퇴사두 집중)",
                  exercises: [
                    { name: "프론트 스쿼트", sets: 4, reps: 8 },
                    { name: "핵 스쿼트", sets: 4, reps: 12 },
                    { name: "레그 익스텐션", sets: 3, reps: 15 },
                    { name: "워킹 런지", sets: 3, reps: 12 },
                    { name: "시티드 카프 레이즈", sets: 4, reps: 15 }
                  ]
                },
                day3_alt: {
                  target: "하체 옵션B (햄스트링/둔근 집중)",
                  exercises: [
                    { name: "데드리프트", sets: 4, reps: 6 },
                    { name: "불가리안 스플릿 스쿼트", sets: 3, reps: 10 },
                    { name: "라잉 레그 컬", sets: 4, reps: 12 },
                    { name: "힙 쓰러스트", sets: 3, reps: 12 },
                    { name: "스탠딩 카프 레이즈", sets: 4, reps: 12 }
                  ]
                },
                day4: {
                  target: "어깨",
                  exercises: [
                    { name: "시티드 덤벨 프레스", sets: 4, reps: 10 },
                    { name: "케이블 레터럴 레이즈", sets: 4, reps: 15 },
                    { name: "페이스 풀", sets: 3, reps: 15 },
                    { name: "리버스 펙 덱", sets: 3, reps: 15 },
                    { name: "프론트 레이즈", sets: 3, reps: 12 }
                  ]
                },
                day5: {
                  target: "이두/삼두",
                  exercises: [
                    { name: "EZ바 컬", sets: 4, reps: 10 },
                    { name: "해머 컬", sets: 3, reps: 12 },
                    { name: "컨센트레이션 컬", sets: 3, reps: 12 },
                    { name: "클로즈 그립 벤치프레스", sets: 4, reps: 10 },
                    { name: "스컬 크러셔", sets: 3, reps: 12 },
                    { name: "트라이셉스 킥백", sets: 3, reps: 12 }
                  ]
                }
              }
            },
            three_split: {
              name: "3분할",
              duration: "2주",
              description: "고볼륨 훈련",
              schedule: {
                day1: {
                  target: "등/어깨",
                  total_sets: 33,
                  exercises: [
                    { name: "풀업", sets: 5, reps: "max" },
                    { name: "바벨 로우", sets: 5, reps: 8 },
                    { name: "케이블 로우", sets: 4, reps: 12 },
                    { name: "스트레이트 암 풀다운", sets: 4, reps: 15 },
                    { name: "오버헤드 프레스", sets: 5, reps: 8 },
                    { name: "사이드 레터럴 레이즈", sets: 5, reps: 15 },
                    { name: "페이스 풀", sets: 5, reps: 15 }
                  ]
                },
                day2: {
                  target: "가슴/팔",
                  total_sets: 30,
                  exercises: [
                    { name: "벤치프레스", sets: 5, reps: 6 },
                    { name: "인클라인 덤벨 프레스", sets: 4, reps: 10 },
                    { name: "딥스", sets: 4, reps: 12 },
                    { name: "케이블 크로스오버", sets: 4, reps: 15 },
                    { name: "바벨 컬", sets: 4, reps: 10 },
                    { name: "해머 컬", sets: 3, reps: 12 },
                    { name: "트라이셉스 푸시다운", sets: 3, reps: 12 },
                    { name: "오버헤드 익스텐션", sets: 3, reps: 12 }
                  ]
                },
                day3: {
                  target: "하체",
                  total_sets: 28,
                  exercises: [
                    { name: "스쿼트", sets: 5, reps: 6 },
                    { name: "레그프레스", sets: 4, reps: 12 },
                    { name: "루마니안 데드리프트", sets: 4, reps: 10 },
                    { name: "레그 컬", sets: 4, reps: 12 },
                    { name: "레그 익스텐션", sets: 4, reps: 15 },
                    { name: "카프 레이즈", sets: 4, reps: 15 },
                    { name: "크런치", sets: 3, reps: 20 }
                  ]
                }
              }
            },
            deloading_2: {
              name: "디로딩",
              duration: "1주",
              description: "볼륨과 강도 50% 감소, 사이클 완료"
            }
          }
        }
      }
    }.freeze

    # ============================================================
    # HELPER METHODS
    # ============================================================
    class << self
      def program_for_level(level)
        numeric = level.to_s.to_i
        case level.to_s.downcase
        when "beginner", "초급"
          BEGINNER
        when "intermediate", "중급"
          INTERMEDIATE
        when "advanced", "고급"
          ADVANCED
        when "shimhyundo", "심현도"
          SHIMHYUNDO
        when "kimsunghwan", "김성환"
          KIMSUNGHWAN
        else
          # Numeric level mapping
          if numeric >= 1 && numeric <= 2
            BEGINNER
          elsif numeric >= 3 && numeric <= 5
            INTERMEDIATE
          elsif numeric >= 6 && numeric <= 8
            ADVANCED
          else
            BEGINNER
          end
        end
      end

      def get_workout(level:, week:, day:)
        program = program_for_level(level)
        return nil unless program

        # Handle different program structures
        if program[:program]
          week_num = [[week, 1].max, program[:weeks]].min
          day_num = [[day, 1].max, 5].min
          program.dig(:program, week_num, day_num)
        elsif program[:phases]
          # For phase-based programs like KIMSUNGHWAN
          nil # Requires different handling
        else
          nil
        end
      end

      def get_shimhyundo_workout(level:, day:)
        level_num = [[level.to_i, 1].max, 8].min
        day_num = [[day.to_i, 1].max, 6].min
        SHIMHYUNDO.dig(:program, level_num, day_num)
      end

      def get_kimsunghwan_phase(phase_name)
        KIMSUNGHWAN.dig(:phases, phase_name.to_sym)
      end

      def training_type_info(type)
        TRAINING_TYPES[type] || TRAINING_TYPES[:strength]
      end

      def all_programs
        {
          beginner: BEGINNER,
          intermediate: INTERMEDIATE,
          advanced: ADVANCED,
          shimhyundo: SHIMHYUNDO,
          kimsunghwan: KIMSUNGHWAN
        }
      end

      def calculate_weight_for_shimhyundo(exercise:, level:, user_height:)
        standards = SHIMHYUNDO[:weight_standards]
        return nil unless standards[exercise.to_sym]

        base_formula = standards[exercise.to_sym][:base]
        multiplier = standards[exercise.to_sym][:level_multiplier][level - 1] || 1

        base_weight = case base_formula
                      when /키 - 100/
                        user_height - 100
                      when /\(키 - 100\) \+ 20/
                        (user_height - 100) + 20
                      when /\(키 - 100\) \+ 40/
                        (user_height - 100) + 40
                      else
                        0
                      end

        (base_weight * multiplier).round
      end
    end
  end
end
