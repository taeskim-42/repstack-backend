# frozen_string_literal: true

require_relative "config"
require_relative "day_simulator"
require_relative "error_logger"
require_relative "report_generator"
require_relative "personas/normal_user"
require_relative "personas/power_user"
require_relative "personas/lazy_user"
require_relative "personas/abuser"
require_relative "personas/edge_case_user"
require_relative "personas/marathon_user"
require_relative "personas/agent_test_user"
require_relative "actions/onboarding_action"
require_relative "actions/condition_check_action"
require_relative "actions/routine_generation_action"
require_relative "actions/exercise_recording_action"
require_relative "actions/workout_completion_action"
require_relative "actions/feedback_action"
require_relative "actions/abuse_action"
require_relative "actions/week_advance_action"
require_relative "validators/data_integrity_validator"
require_relative "validators/concurrency_validator"
require_relative "validators/rate_limit_validator"
require_relative "validators/business_logic_validator"

module Simulation
  class Runner
    attr_reader :config, :users, :stats, :error_logger

    def initialize(mode: :smoke)
      @config = Config.new(mode: mode)
      @users = []
      @stats = Concurrent::Hash.new(0)
      @stats_mutex = Mutex.new
      @progress_mutex = Mutex.new
      @error_logger = ErrorLogger.new(log_dir: Config::LOG_DIR)
      @start_time = Time.current
    end

    def run
      $stdout.sync = true
      ensure_db_pool!

      puts "=" * 65
      puts "  RepStack Simulation Starting"
      puts "  Mode: #{config.mode} | Users: #{config.total_users} | Days: #{config.days} | Workers: #{config.workers}"
      puts "=" * 65
      puts

      create_users
      simulate_days
      validate
      report

      puts "\nSimulation finished in #{elapsed}."
      print_log_paths
    end

    def validate_only
      sim_users = User.where("email LIKE ?", "%#{Config::EMAIL_DOMAIN}")
      @users = sim_users.map { |u| { user: u, persona: Personas::NormalUser.new } }
      puts "Validating #{sim_users.count} simulation users..."
      validate
      report
    end

    def cleanup
      email_pattern = "%#{Config::EMAIL_DOMAIN}"
      sim_users = User.where("email LIKE ?", email_pattern)
      count = sim_users.count

      if count.zero?
        puts "No simulation users found."
        return
      end

      puts "Cleaning up #{count} simulation users and all related data..."

      user_ids = sim_users.pluck(:id)

      # Delete in dependency order (all tables with user_id FK)
      WorkoutSet.where(workout_session_id: WorkoutSession.where(user_id: user_ids).select(:id)).delete_all
      WorkoutSession.where(user_id: user_ids).delete_all
      WorkoutRecord.where(user_id: user_ids).delete_all if defined?(WorkoutRecord)
      RoutineExercise.where(workout_routine_id: WorkoutRoutine.where(user_id: user_ids).select(:id)).delete_all
      WorkoutRoutine.where(user_id: user_ids).delete_all
      TrainingProgram.where(user_id: user_ids).delete_all
      ConditionLog.where(user_id: user_ids).delete_all
      WorkoutFeedback.where(user_id: user_ids).delete_all
      ChatMessage.where(user_id: user_ids).delete_all
      OnboardingAnalytics.where(user_id: user_ids).delete_all if defined?(OnboardingAnalytics)
      FitnessTestSubmission.where(user_id: user_ids).delete_all if defined?(FitnessTestSubmission)
      LevelTestVerification.where(user_id: user_ids).delete_all if defined?(LevelTestVerification)
      if defined?(AgentConversationMessage) && defined?(AgentSession)
        AgentConversationMessage.where(
          agent_session_id: AgentSession.where(user_id: user_ids).select(:id)
        ).delete_all
        AgentSession.where(user_id: user_ids).delete_all
      end
      UserProfile.where(user_id: user_ids).delete_all

      # Clear rate limit cache keys
      user_ids.each do |uid|
        %i[routine_generation exercise_replacement routine_regeneration].each do |action|
          key = "rate_limit:routine:#{uid}:#{action}:#{Date.current}"
          Rails.cache.delete(key)
        end
      end

      sim_users.delete_all

      puts "Deleted #{count} users and all associated data."
    end

    # Thread-safe stat increment (called by DaySimulator and Actions)
    def increment_stat(key, amount = 1)
      @stats_mutex.synchronize { @stats[key] = (@stats[key] || 0) + amount }
    end

    def stat(key)
      @stats_mutex.synchronize { @stats[key] || 0 }
    end

    private

    # Ensure DB connection pool is large enough for parallel workers
    def ensure_db_pool!
      return unless config.parallel?

      current_pool = ActiveRecord::Base.connection_pool.size
      needed = config.workers + 5 # extra headroom

      if current_pool < needed
        puts "Expanding DB connection pool: #{current_pool} → #{needed}"
        ActiveRecord::Base.connection_pool.disconnect!
        config_hash = ActiveRecord::Base.connection_db_config.configuration_hash.dup
        config_hash[:pool] = needed
        ActiveRecord::Base.establish_connection(config_hash)
      end
    end

    def create_users
      puts "Creating #{config.total_users} users..."

      config.persona_counts.each do |persona_type, count|
        persona_class = persona_class_for(persona_type)
        count.times do |i|
          user = create_simulation_user(persona_type, i)
          @users << { user: user, persona: persona_class.new }
          increment_stat(:users_created)
        end
        puts "  #{persona_type}: #{count} users created"
      end
      puts
    end

    def simulate_days
      compact_mode = config.days > 30

      config.days.times do |day_index|
        day_number = day_index + 1
        day_start = Time.current

        unless compact_mode
          puts "--- Day #{day_number} (#{config.workers} workers) ---"
        end

        if config.parallel?
          simulate_day_parallel(day_number)
        else
          simulate_day_sequential(day_number)
        end

        day_elapsed = (Time.current - day_start).round(1)
        error_count = error_logger.count

        if compact_mode
          # Print every 7 days or on milestones
          if day_number % 7 == 0 || day_number == config.days || error_count > 0
            pct = (day_number.to_f / config.days * 100).round(1)
            week = (day_number / 7.0).ceil
            print "  Day #{day_number}/#{config.days} (#{pct}%) Week #{week} | #{format_time(day_elapsed)}/day | errors: #{error_count}\n"
          end
        else
          puts "  Day #{day_number} done in #{format_time(day_elapsed)} | Errors so far: #{error_count}"
          puts
        end
      end
    end

    def simulate_day_sequential(day_number)
      @users.each_with_index do |entry, idx|
        run_user_day(entry, day_number)
        print_progress(idx + 1, @users.size) if should_print_progress?(idx + 1)
      end
    end

    def simulate_day_parallel(day_number)
      queue = Queue.new
      @users.each_with_index { |entry, idx| queue << [entry, idx] }

      completed = Concurrent::AtomicFixnum.new(0)
      total = @users.size

      threads = config.workers.times.map do
        Thread.new do
          loop do
            entry, _idx = queue.pop(true) rescue break

            ActiveRecord::Base.connection_pool.with_connection do
              run_user_day(entry, day_number)
            end

            done = completed.increment
            print_progress_threadsafe(done, total) if should_print_progress?(done)
          end
        end
      end

      threads.each(&:join)
    end

    def run_user_day(entry, day_number)
      user = entry[:user]
      persona = entry[:persona]

      simulator = DaySimulator.new(
        user: user,
        persona: persona,
        day_number: day_number,
        stats: self,
        error_logger: error_logger
      )
      simulator.run
    end

    def validate
      puts "Running validations..."
      @validation_results = {}

      validators = {
        "DATA INTEGRITY" => Validators::DataIntegrityValidator,
        "CONCURRENCY"    => Validators::ConcurrencyValidator,
        "RATE LIMITING"  => Validators::RateLimitValidator,
        "BUSINESS LOGIC" => Validators::BusinessLogicValidator
      }

      user_ids = @users.map { |e| e[:user].id }

      validators.each do |name, klass|
        result = klass.new(user_ids: user_ids).validate
        @validation_results[name] = result
        status = result[:pass] ? "PASS" : "FAIL"
        puts "  #{name}: [#{status}] #{result[:summary]}"
      end
    end

    def report
      puts

      generator = ReportGenerator.new(
        config: config,
        users: @users,
        stats: @stats.to_h,
        error_logger: error_logger,
        validation_results: @validation_results || {},
        elapsed: elapsed
      )
      generator.print_report
    end

    def print_log_paths
      paths = error_logger.log_paths
      puts
      puts "Log files:"
      puts "  Errors:  #{paths[:summary]}"
      puts "  Details: #{paths[:detail]}"
    end

    def create_simulation_user(persona_type, index)
      email = "sim_#{persona_type}_#{index}#{Config::EMAIL_DOMAIN}"
      User.create!(
        email: email,
        name: "Sim #{persona_type.to_s.titleize} #{index}",
        password: "simulation_password_123",
        password_confirmation: "simulation_password_123"
      )
    end

    def persona_class_for(type)
      case type
      when :normal    then Personas::NormalUser
      when :power     then Personas::PowerUser
      when :lazy      then Personas::LazyUser
      when :abuser    then Personas::Abuser
      when :edge_case then Personas::EdgeCaseUser
      when :marathon    then Personas::MarathonUser
      when :agent_test  then Personas::AgentTestUser
      end
    end

    def should_print_progress?(current)
      step = [@users.size / 20, 1].max
      current % step == 0 || current == @users.size
    end

    def print_progress(current, total)
      pct = (current.to_f / total * 100).round(1)
      print "  [#{current}/#{total}] #{pct}%\r"
    end

    def print_progress_threadsafe(current, total)
      @progress_mutex.synchronize do
        pct = (current.to_f / total * 100).round(1)
        print "  [#{current}/#{total}] #{pct}% | errors: #{error_logger.count}\r"
      end
    end

    def elapsed
      format_time((Time.current - @start_time).round(1))
    end

    def format_time(seconds)
      if seconds > 3600
        "#{(seconds / 3600).round(1)}h"
      elsif seconds > 60
        "#{(seconds / 60).round(1)}m"
      else
        "#{seconds}s"
      end
    end
  end
end
