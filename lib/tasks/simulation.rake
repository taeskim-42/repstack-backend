# frozen_string_literal: true

namespace :simulation do
  desc "Smoke test: 10 users × 2 days (sequential)"
  task smoke: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :smoke).run
  end

  desc "100 users × 7 days (50 workers parallel)"
  task hundred: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :hundred).run
  end

  desc "Full run: 1000 users × 7 days (50 workers parallel)"
  task run: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :run).run
  end

  desc "Yearly: 1 marathon user × 365 days (long-term stability test)"
  task yearly: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :yearly).run
  end

  desc "Agent test: 10 users × 28 days (4 weeks via Agent Service)"
  task agent: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :agent).run
  end

  desc "Validate existing simulation data"
  task validate: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :smoke).validate_only
  end

  desc "Cleanup all simulation data (@simulation.test users)"
  task cleanup: :environment do
    require_relative "../simulation/runner"
    Simulation::Runner.new(mode: :smoke).cleanup
  end
end
