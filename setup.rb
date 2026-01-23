#!/usr/bin/env ruby

require 'securerandom'

# RepStack Backend Setup Script
puts "🏃‍♂️ RepStack Backend Setup Script"
puts "================================="

# Check Ruby version
puts "\n📋 Checking Ruby version..."
ruby_version = RUBY_VERSION
puts "Ruby version: #{ruby_version}"

if Gem::Version.new(ruby_version) < Gem::Version.new("3.0.0")
  puts "⚠️  Warning: Ruby version should be 3.0+ for Rails 8"
end

# Check if bundler is available
puts "\n📦 Checking bundler..."
begin
  require 'bundler'
  puts "✅ Bundler is available (version #{Bundler::VERSION})"
rescue LoadError
  puts "❌ Bundler is not available. Please install with: gem install bundler"
  exit 1
end

# Check if PostgreSQL is running
puts "\n🐘 Checking PostgreSQL..."
begin
  require 'pg'
  puts "✅ PostgreSQL gem is available"
rescue LoadError
  puts "⚠️  PostgreSQL gem not yet installed (will be installed with bundle install)"
end

# Environment file check
puts "\n🔐 Checking environment configuration..."
env_file_path = File.join(__dir__, '.env')
env_example_path = File.join(__dir__, '.env.example')

unless File.exist?(env_file_path)
  puts "📄 Creating .env file from template..."

  env_content = <<~ENV
    # Claude AI API Key (required for AI routine generation)
    ANTHROPIC_API_KEY=your_claude_api_key_here

    # JWT Secret Key (required for authentication)
    JWT_SECRET_KEY=#{SecureRandom.hex(32)}

    # Database Configuration (if needed)
    # DATABASE_URL=postgresql://username:password@localhost/repstack_backend_development

    # Rails Environment
    RAILS_ENV=development
  ENV

  File.write(env_file_path, env_content)
  puts "✅ Created .env file with default configuration"
  puts "⚠️  Please update ANTHROPIC_API_KEY in .env file"
else
  puts "✅ .env file already exists"
end

# Gemfile check
puts "\n💎 Checking Gemfile..."
gemfile_path = File.join(__dir__, 'Gemfile')
gemfile_content = File.read(gemfile_path)

required_gems = [ 'bcrypt', 'jwt', 'graphql', 'pg', 'rails' ]
missing_gems = required_gems.reject { |gem| gemfile_content.include?(gem) }

if missing_gems.empty?
  puts "✅ All required gems are in Gemfile"
else
  puts "❌ Missing gems: #{missing_gems.join(', ')}"
end

# Check if models exist
puts "\n🗄️  Checking models..."
models_path = File.join(__dir__, 'app', 'models')
required_models = [ 'user.rb', 'user_profile.rb', 'workout_session.rb', 'workout_set.rb', 'workout_routine.rb', 'routine_exercise.rb' ]

missing_models = required_models.reject { |model| File.exist?(File.join(models_path, model)) }

if missing_models.empty?
  puts "✅ All required models exist"
else
  puts "❌ Missing models: #{missing_models.join(', ')}"
end

# Check if migrations exist
puts "\n🔄 Checking migrations..."
migrations_path = File.join(__dir__, 'db', 'migrate')
if Dir.exist?(migrations_path)
  migration_files = Dir.entries(migrations_path).reject { |f| f.start_with?('.') }
  puts "✅ Found #{migration_files.count} migration files"
  migration_files.each { |file| puts "   - #{file}" }
else
  puts "❌ No migrations directory found"
end

# GraphQL check
puts "\n🔗 Checking GraphQL setup..."
graphql_schema_path = File.join(__dir__, 'app', 'graphql', 'repstack_backend_schema.rb')
mutations_path = File.join(__dir__, 'app', 'graphql', 'mutations')
queries_path = File.join(__dir__, 'app', 'graphql', 'queries')

if File.exist?(graphql_schema_path)
  puts "✅ GraphQL schema exists"
else
  puts "❌ GraphQL schema missing"
end

if Dir.exist?(mutations_path)
  mutation_files = Dir.entries(mutations_path).reject { |f| f.start_with?('.') || f == 'base_mutation.rb' }
  puts "✅ Found #{mutation_files.count} mutation files"
else
  puts "❌ Mutations directory missing"
end

if Dir.exist?(queries_path)
  query_files = Dir.entries(queries_path).reject { |f| f.start_with?('.') }
  puts "✅ Found #{query_files.count} query files"
else
  puts "❌ Queries directory missing"
end

puts "\n🚀 Setup Instructions"
puts "===================="
puts "1. Install dependencies: bundle install"
puts "2. Setup database: rails db:create"
puts "3. Run migrations: rails db:migrate"
puts "4. Update .env file with your ANTHROPIC_API_KEY"
puts "5. Start server: rails server"
puts "6. Test GraphQL endpoint at: http://localhost:3000/graphql"

puts "\n📖 Documentation"
puts "================="
puts "- See IMPLEMENTATION_STATUS.md for complete API documentation"
puts "- See README.md for project overview"

puts "\n✨ Setup complete! Ready to run RepStack Backend."
