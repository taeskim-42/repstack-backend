# frozen_string_literal: true

module Localizable
  extend ActiveSupport::Concern

  SUPPORTED_LOCALES = %w[ko en ja].freeze
  DEFAULT_LOCALE = "ko"

  TRANSLATIONS = {
    days: {
      ko: %w[일요일 월요일 화요일 수요일 목요일 금요일 토요일],
      en: %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday],
      ja: %w[日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日]
    },
    tiers: {
      ko: { "beginner" => "초급", "intermediate" => "중급", "advanced" => "고급" },
      en: { "beginner" => "Beginner", "intermediate" => "Intermediate", "advanced" => "Advanced" },
      ja: { "beginner" => "初級", "intermediate" => "中級", "advanced" => "上級" }
    },
    fitness_factors: {
      ko: { "strength" => "근력", "muscular_endurance" => "근지구력", "sustainability" => "지속력", "power" => "순발력", "cardiovascular" => "심폐지구력" },
      en: { "strength" => "Strength", "muscular_endurance" => "Muscular Endurance", "sustainability" => "Sustainability", "power" => "Power", "cardiovascular" => "Cardiovascular" },
      ja: { "strength" => "筋力", "muscular_endurance" => "筋持久力", "sustainability" => "持続力", "power" => "瞬発力", "cardiovascular" => "心肺持久力" }
    },
    conditions: {
      ko: { "excellent" => "최상", "good" => "양호", "moderate" => "보통", "poor" => "나쁨" },
      en: { "excellent" => "Excellent", "good" => "Good", "moderate" => "Moderate", "poor" => "Poor" },
      ja: { "excellent" => "最高", "good" => "良好", "moderate" => "普通", "poor" => "不良" }
    },
    exercise_tiers: {
      ko: { "poor" => "부족", "fair" => "보통", "good" => "양호", "excellent" => "우수", "elite" => "엘리트" },
      en: { "poor" => "Poor", "fair" => "Fair", "good" => "Good", "excellent" => "Excellent", "elite" => "Elite" },
      ja: { "poor" => "不足", "fair" => "普通", "good" => "良好", "excellent" => "優秀", "elite" => "エリート" }
    },
    training_methods: {
      ko: { "fixed_sets_reps" => "정해진 세트/횟수", "total_reps_fill" => "채우기", "max_sets_at_fixed_reps" => "지속력 측정", "tabata" => "타바타", "explosive" => "폭발적 수행" },
      en: { "fixed_sets_reps" => "Fixed Sets & Reps", "total_reps_fill" => "Total Reps Fill", "max_sets_at_fixed_reps" => "Max Sets at Fixed Reps", "tabata" => "Tabata", "explosive" => "Explosive" },
      ja: { "fixed_sets_reps" => "固定セット・回数", "total_reps_fill" => "トータルレップ", "max_sets_at_fixed_reps" => "持続力測定", "tabata" => "タバタ", "explosive" => "爆発的実行" }
    },
    grades: {
      ko: { "normal" => "정상인", "healthy" => "건강인", "athletic" => "운동인" },
      en: { "normal" => "Normal", "healthy" => "Healthy", "athletic" => "Athletic" },
      ja: { "normal" => "一般", "healthy" => "健康", "athletic" => "アスリート" }
    },
    feedback_categories: {
      ko: { "difficulty" => "난이도", "energy" => "에너지", "enjoyment" => "만족도", "pain" => "통증", "time" => "시간" },
      en: { "difficulty" => "Difficulty", "energy" => "Energy", "enjoyment" => "Enjoyment", "pain" => "Pain", "time" => "Time" },
      ja: { "difficulty" => "難易度", "energy" => "エネルギー", "enjoyment" => "満足度", "pain" => "痛み", "time" => "時間" }
    },
    condition_inputs: {
      ko: { "sleep" => "수면", "fatigue" => "피로도", "stress" => "스트레스", "soreness" => "근육통", "motivation" => "의욕" },
      en: { "sleep" => "Sleep", "fatigue" => "Fatigue", "stress" => "Stress", "soreness" => "Soreness", "motivation" => "Motivation" },
      ja: { "sleep" => "睡眠", "fatigue" => "疲労度", "stress" => "ストレス", "soreness" => "筋肉痛", "motivation" => "意欲" }
    },
    split_types: {
      ko: { "full_body" => "무분할", "upper_lower" => "2분할 (상/하)", "push_pull_legs" => "3분할 (밀기/당기기/하체)", "four_day" => "4분할", "five_day" => "5분할", "fitness_factor_based" => "체력요인 기반" },
      en: { "full_body" => "Full Body", "upper_lower" => "Upper/Lower Split", "push_pull_legs" => "Push/Pull/Legs", "four_day" => "4-Day Split", "five_day" => "5-Day Split", "fitness_factor_based" => "Fitness Factor Based" },
      ja: { "full_body" => "全身", "upper_lower" => "上半身/下半身", "push_pull_legs" => "プッシュ/プル/レッグ", "four_day" => "4分割", "five_day" => "5分割", "fitness_factor_based" => "体力要因ベース" }
    }
  }.freeze

  class_methods do
    # Translates a key in a given category to the target locale.
    # Falls back to Korean if locale is unsupported or translation is missing.
    def translate(category, key, locale = "ko")
      Localizable.translate(category, key, locale)
    end
  end

  # Allow Localizable.translate(...) calls directly from GraphQL resolvers
  def self.translate(category, key, locale = "ko")
    locale = locale.to_s
    locale = DEFAULT_LOCALE unless SUPPORTED_LOCALES.include?(locale)

    translations = TRANSLATIONS.dig(category, locale.to_sym)
    return key.to_s if translations.nil?

    if translations.is_a?(Array)
      translations[key.to_i] || key.to_s
    else
      translations[key.to_s] || TRANSLATIONS.dig(category, :ko, key.to_s) || key.to_s
    end
  end
end
