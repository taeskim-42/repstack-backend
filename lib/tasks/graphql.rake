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
  end
end
