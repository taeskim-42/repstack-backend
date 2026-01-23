# frozen_string_literal: true

# Circuitbox configuration for circuit breaker pattern
# See: https://github.com/yammer/circuitbox
#
# Circuitbox 2.x uses a different API than 1.x
# Configuration is done per-circuit, not globally

# Use memory store for development, Rails cache for production
# Memory store is faster but doesn't share state across processes
Circuitbox.default_circuit_store = if Rails.env.production?
                                     Rails.cache
else
                                     Circuitbox::MemoryStore.new
end

# Optional: Set a custom notifier for circuit events
# Circuitbox.default_notifier = MyCustomNotifier.new

# Set up circuit breaker monitoring via ActiveSupport::Notifications
# This is safer than directly attaching callbacks to circuits
ActiveSupport::Notifications.subscribe("circuit_open.circuitbox") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  circuit_name = event.payload[:circuit]
  Rails.logger.error("[Circuit:#{circuit_name}] Circuit OPENED - Too many failures, rejecting requests")
  MetricsService.record_circuit_trip(circuit_name.to_s) if defined?(MetricsService)
end

ActiveSupport::Notifications.subscribe("circuit_close.circuitbox") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  circuit_name = event.payload[:circuit]
  Rails.logger.info("[Circuit:#{circuit_name}] Circuit CLOSED - Service recovered, accepting requests")
end
