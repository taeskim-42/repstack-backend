# frozen_string_literal: true

module AiTrainer
  module Data
    module Programs
      # Intermediate program data (중급) - repeating week
      module Intermediate
        INTERMEDIATE = {
          level: "intermediate",
          korean: "중급",
          numeric_levels: [ 3, 4, 5 ],
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
      end
    end
  end
end
