# frozen_string_literal: true

class EnablePgvector < ActiveRecord::Migration[8.1]
  # Disable DDL transaction to allow extension check without rolling back
  disable_ddl_transaction!

  def change
    # Enable pgvector extension for vector similarity search
    # Required for RAG (Retrieval Augmented Generation) functionality
    #
    # Note: In production (Railway), pgvector is available.
    # In development, this may fail if pgvector is not installed locally.
    if pgvector_available?
      enable_extension "vector"
    else
      puts "WARNING: pgvector extension not available. Install pgvector for vector search functionality."
      puts "RAG features will be disabled in this environment."
    end
  end

  private

  def pgvector_available?
    result = execute("SELECT * FROM pg_available_extensions WHERE name = 'vector'")
    result.any?
  rescue StandardError
    false
  end
end
