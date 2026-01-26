#!/bin/bash
set -e

if [ "$WORKER_ONLY" = "true" ]; then
  echo "Starting Sidekiq worker..."
  # Start a simple health check server on PORT (Railway healthcheck needs this)
  if [ -n "$PORT" ]; then
    ruby -e "
      require 'socket'
      Thread.new do
        server = TCPServer.new('0.0.0.0', ${PORT})
        loop do
          client = server.accept
          request = client.gets
          if request&.include?('/health')
            client.print \"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK\"
          else
            client.print \"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK\"
          end
          client.close
        end
      end
      sleep
    " &
  fi
  exec bundle exec sidekiq -C config/sidekiq.yml
else
  echo "Starting web server..."
  bundle exec rails db:prepare
  exec bundle exec puma -C config/puma.rb
fi
