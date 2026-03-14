# frozen_string_literal: true

module AiTrainer
  module Data
    module Programs
      # Beginner program data (초급) - 4 weeks
      module Beginner
        BEGINNER = {
          level: "beginner",
          korean: "초급",
          numeric_levels: [ 1, 2 ],
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
      end
    end
  end
end
