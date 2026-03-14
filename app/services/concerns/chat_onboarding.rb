# frozen_string_literal: true

require_relative "chat_onboarding/greeting_builder"
require_relative "chat_onboarding/form_handler"

# Extracted from ChatService: daily greeting, welcome message,
# level assessment, and today-routine triggers.
module ChatOnboarding
  extend ActiveSupport::Concern

  include GreetingBuilder
  include FormHandler
end
