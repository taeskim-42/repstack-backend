# frozen_string_literal: true

namespace :graphql do
  namespace :schema do
    desc "Dump the GraphQL schema to schema.graphql"
    task dump: :environment do
      schema_definition = RepstackBackendSchema.to_definition
      schema_path = Rails.root.join("schema.graphql")
      File.write(schema_path, schema_definition)
      puts "GraphQL schema dumped to #{schema_path}"
    end

    desc "Generate API documentation using SpectaQL"
    task docs: :dump do
      puts "Generating API documentation..."
      system("npx spectaql spectaql.yml")
      puts "Documentation generated in docs/api/"
    end

    desc "Validate GraphQL schema matches database schema"
    task validate: :environment do
      validator = SchemaValidator.new
      result = validator.print_report

      exit(1) unless result.valid?
    end

    desc "Full validation: dump schema, validate, and generate docs"
    task full_check: :environment do
      puts "Step 1: Validating schema..."
      Rake::Task["graphql:schema:validate"].invoke

      puts "\nStep 2: Dumping schema..."
      Rake::Task["graphql:schema:dump"].invoke

      puts "\nStep 3: Generating documentation..."
      Rake::Task["graphql:schema:docs"].reenable
      Rake::Task["graphql:schema:docs"].invoke

      puts "\n✅ Full check completed!"
    end
  end
end
