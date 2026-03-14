# frozen_string_literal: true

module AiTrainer
  module Data
    module Programs
      # Advanced program data (고급) - repeating week + breakthrough strategies
      module Advanced
        ADVANCED = {
          level: "advanced",
          korean: "고급",
          numeric_levels: [ 6, 7, 8 ],
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
      end
    end
  end
end
