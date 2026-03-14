# frozen_string_literal: true

module AiTrainer
  module Data
    module Programs
      # Kim Sunghwan routine data (김성환) - phase-based
      module Kimsunghwan
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
      end
    end
  end
end
