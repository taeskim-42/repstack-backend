# frozen_string_literal: true

namespace :onboarding do
  desc "Show onboarding analytics weekly report"
  task report: :environment do
    puts "=" * 60
    puts "📊 Onboarding Analytics Report"
    puts "=" * 60

    report = OnboardingAnalytics.weekly_report

    puts "\n📅 Period: #{report[:period]}"
    puts "\n📈 Overview:"
    puts "   Total Sessions: #{report[:total_sessions]}"
    puts "   Completion Rate: #{report[:completion_rate]}%"
    puts "   Average Turns: #{report[:average_turns]}"

    if report[:abandonment_points].any?
      puts "\n❌ Abandonment by Turn:"
      report[:abandonment_points].each do |turn, count|
        puts "   Turn #{turn}: #{count} users"
      end
    end

    if report[:info_collection_rate].any?
      puts "\n📋 Info Collection Rate:"
      report[:info_collection_rate].each do |key, rate|
        puts "   #{key}: #{rate}%"
      end
    end

    puts "\n" + "=" * 60
  end

  desc "Show stats by prompt version"
  task version_stats: :environment do
    puts "=" * 60
    puts "📊 Stats by Prompt Version (Last 30 days)"
    puts "=" * 60

    stats = OnboardingAnalytics.by_prompt_version_stats(days: 30)

    if stats.empty?
      puts "\nNo data available."
    else
      stats.each do |s|
        completion_rate = s.total.positive? ? (s.completed_count.to_f / s.total * 100).round(1) : 0
        puts "\n#{s.prompt_version || 'unknown'}:"
        puts "   Total: #{s.total}"
        puts "   Completed: #{s.completed_count} (#{completion_rate}%)"
        puts "   Avg Turns: #{s.avg_turns}"
      end
    end

    puts "\n" + "=" * 60
  end

  desc "Export failed conversations for analysis"
  task export_failures: :environment do
    failures = OnboardingAnalytics.recent(30).abandoned.includes(:user)

    if failures.empty?
      puts "No failed conversations in the last 30 days."
      return
    end

    puts "Exporting #{failures.count} failed conversations..."

    output = failures.map do |a|
      {
        session_id: a.session_id,
        turn_count: a.turn_count,
        collected_info: a.collected_info,
        conversation: a.conversation_log,
        prompt_version: a.prompt_version,
        created_at: a.created_at
      }
    end

    file_path = Rails.root.join("tmp", "onboarding_failures_#{Date.current}.json")
    File.write(file_path, JSON.pretty_generate(output))

    puts "Exported to: #{file_path}"
  end

  desc "Run simulation test"
  task :simulate, [:count] => :environment do |_t, args|
    count = (args[:count] || 10).to_i
    puts "Running simulation with #{count} personas..."

    system("ruby #{Rails.root.join('scripts', 'onboarding_simulation.rb')} #{count}")
  end
end
