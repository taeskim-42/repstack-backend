# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # API-only app — no cookie-based auth
    # Team system connects locally, so no authentication required
  end
end
