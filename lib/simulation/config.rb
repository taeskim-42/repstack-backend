# frozen_string_literal: true

module Simulation
  class Config
    PRESETS = {
      smoke:    { users: 10,   days: 2,   workers: 1  },
      hundred:  { users: 100,  days: 7,   workers: 50 },
      run:      { users: 1000, days: 7,   workers: 50 },
      yearly:   { users: 1,    days: 365, workers: 1, persona_override: :marathon },
      agent:    { users: 10,   days: 28,  workers: 1, persona_override: :agent_test }
    }.freeze

    PERSONA_DISTRIBUTION = {
      normal:    0.6,
      power:     0.1,
      lazy:      0.1,
      abuser:    0.1,
      edge_case: 0.1
    }.freeze

    EMAIL_DOMAIN = "@simulation.test"
    LOG_DIR = Rails.root.join("log", "simulation")

    attr_reader :total_users, :days, :mode, :workers, :persona_override

    def initialize(mode: :smoke)
      @mode = mode
      preset = PRESETS.fetch(mode)
      @total_users = preset[:users]
      @days = preset[:days]
      @workers = preset[:workers]
      @persona_override = preset[:persona_override]
    end

    def parallel?
      workers > 1
    end

    def persona_counts
      if persona_override
        { persona_override => total_users }
      else
        PERSONA_DISTRIBUTION.transform_values { |ratio| (total_users * ratio).round }
      end
    end

    def simulation_email?(email)
      email&.end_with?(EMAIL_DOMAIN)
    end

    def log_file
      LOG_DIR.join("simulation_#{mode}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.log")
    end

    def error_log_file
      LOG_DIR.join("errors_#{mode}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.log")
    end
  end
end
