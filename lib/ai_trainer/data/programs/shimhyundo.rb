# frozen_string_literal: true

module AiTrainer
  module Data
    module Programs
      # Shimhyundo full-body routine data (심현도 무분할) - 8 levels
      module Shimhyundo
        SHIMHYUNDO = {
          name: "심현도 무분할 루틴",
          type: "full_body",
          levels: 8,
          days_per_week: 6, # 월~토
          weight_standards: {
            bench_press: { base: "키 - 100", level_multiplier: [ 1, 1.14, 1.28, 1.42, 1.56, 1.7 ] },
            squat: { base: "(키 - 100) + 20", level_multiplier: [ 1, 1.14, 1.28, 1.42, 1.56, 1.7 ] },
            deadlift: { base: "(키 - 100) + 40", level_multiplier: [ 1, 1.14, 1.28, 1.42, 1.56, 1.7 ] }
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
              6 => { exercises: [ { name: "자율", target: "전체", sets: nil, reps: nil, weight: nil, how_to: "자율 운동" } ] }
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
              6 => { exercises: [ { name: "자율", target: "전체", sets: nil, reps: nil, weight: nil, how_to: "자율 운동" } ] }
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
      end
    end
  end
end
