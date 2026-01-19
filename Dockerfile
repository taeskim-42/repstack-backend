# syntax=docker/dockerfile:1

# =============================================================================
# Base stage - common dependencies
# =============================================================================
FROM docker.io/library/ruby:3.4.1-slim AS base

WORKDIR /rails

# Install base dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libpq-dev \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set environment defaults
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle"

# =============================================================================
# Build stage - install gems and precompile
# =============================================================================
FROM base AS build

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      pkg-config \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install gems
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test"

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Precompile bootsnap for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# =============================================================================
# Development stage - includes dev/test dependencies
# =============================================================================
FROM base AS development

# Install build dependencies for gem compilation
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      pkg-config \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install all gems including dev/test
ENV BUNDLE_DEPLOYMENT="0" \
    BUNDLE_WITHOUT=""

COPY Gemfile Gemfile.lock ./
RUN bundle install

# Set development environment
ENV RAILS_ENV="development" \
    PORT=3000 \
    PROMETHEUS_EXPORTER_PORT=9394

EXPOSE 3000 9394

# Default command for development
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

# =============================================================================
# Production stage - minimal runtime image (MUST BE LAST for Railway)
# =============================================================================
FROM base AS production

# Create non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Copy built artifacts from build stage
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Set proper ownership
RUN chown -R rails:rails /rails

# Switch to non-root user
USER rails

# Expose ports
# 3000 - Rails application
# 9394 - Prometheus metrics exporter
ENV PORT=3000 \
    PROMETHEUS_EXPORTER_PORT=9394
EXPOSE 3000 9394

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start server with database migration
CMD ["sh", "-c", "bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
