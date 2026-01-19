# frozen_string_literal: true

module GraphQL
  module TestHelpers
    # Execute a GraphQL query with the given variables and context
    def execute_graphql(query:, variables: {}, context: {})
      RepstackBackendSchema.execute(
        query,
        variables: variables,
        context: context
      )
    end

    # Execute a GraphQL query as an authenticated user
    def execute_graphql_as(user, query:, variables: {})
      execute_graphql(
        query: query,
        variables: variables,
        context: { current_user: user }
      )
    end

    # Extract data from GraphQL response
    def graphql_data(response)
      response["data"]
    end

    # Extract errors from GraphQL response
    def graphql_errors(response)
      response["errors"]
    end

    # Check if response has errors
    def graphql_success?(response)
      response["errors"].nil? || response["errors"].empty?
    end

    # Build a mutation query string
    def build_mutation(name, input_type: nil, fields:)
      args = input_type ? "($input: #{input_type}!)" : ""
      input_arg = input_type ? "(input: $input)" : ""

      <<~GRAPHQL
        mutation#{args} {
          #{name}#{input_arg} {
            #{fields}
            errors
          }
        }
      GRAPHQL
    end
  end
end
