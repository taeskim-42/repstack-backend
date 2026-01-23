# frozen_string_literal: true

FactoryBot.define do
  factory :condition_log do
    user
    date { Date.current }
    energy_level { 3 }
    stress_level { 2 }
    sleep_quality { 4 }
    soreness { { "legs" => 2 } }
    motivation { 4 }
    available_time { 60 }
    notes { nil }

    trait :high_energy do
      energy_level { 5 }
      stress_level { 1 }
      sleep_quality { 5 }
      motivation { 5 }
    end

    trait :low_energy do
      energy_level { 1 }
      stress_level { 5 }
      sleep_quality { 1 }
      motivation { 2 }
    end
  end
end
