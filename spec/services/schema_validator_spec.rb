# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchemaValidator do
  subject(:validator) { described_class.new }

  describe "#validate" do
    it "returns a Result struct" do
      result = validator.validate
      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
      expect(result).to respond_to(:warnings)
    end

    it "validates all model-type mappings" do
      expect(SchemaValidator::MODEL_TYPE_MAPPING).not_to be_empty
    end
  end

  describe "#validate_model" do
    context "with User model" do
      let(:result) { validator.validate_model(User, Types::UserType) }

      it "does not expose password_digest" do
        # password_digest should be in SECURITY_EXCLUDED_COLUMNS
        error_fields = result[:errors].map(&:field)
        expect(error_fields).not_to include("password_digest")
      end
    end

    context "with WorkoutSession model" do
      let(:result) { validator.validate_model(WorkoutSession, Types::WorkoutSessionType) }

      it "exposes status field" do
        error_fields = result[:errors].map(&:field)
        expect(error_fields).not_to include("status")
      end

      it "exposes total_duration field" do
        error_fields = result[:errors].map(&:field)
        expect(error_fields).not_to include("total_duration")
      end
    end

    context "with WorkoutRoutine model" do
      let(:result) { validator.validate_model(WorkoutRoutine, Types::WorkoutRoutineType) }

      it "has no nullable mismatches for optional fields" do
        nullable_errors = result[:errors].select { |e| e.issue.include?("Nullable") }
        optional_fields = %w[workout_type day_of_week estimated_duration]

        optional_fields.each do |field|
          expect(nullable_errors.map(&:field)).not_to include(field),
            "Expected #{field} to not have nullable mismatch"
        end
      end
    end

    context "with RoutineExercise model" do
      let(:result) { validator.validate_model(RoutineExercise, Types::RoutineExerciseType) }

      it "has no nullable mismatches for optional fields" do
        nullable_errors = result[:errors].select { |e| e.issue.include?("Nullable") }
        optional_fields = %w[target_muscle sets reps rest_duration_seconds range_of_motion how_to purpose]

        optional_fields.each do |field|
          expect(nullable_errors.map(&:field)).not_to include(field),
            "Expected #{field} to not have nullable mismatch"
        end
      end
    end
  end

  describe "#print_report" do
    it "outputs a report" do
      expect { validator.print_report }.to output(/GraphQL-DB Schema Validation Report/).to_stdout
    end
  end

  describe "schema sync" do
    it "all GraphQL types are in sync with database" do
      result = validator.validate

      if result.errors.any?
        error_messages = result.errors.map do |e|
          "[#{e.model}] #{e.field}: #{e.issue}"
        end.join("\n  ")

        fail "GraphQL-DB schema mismatch detected:\n  #{error_messages}"
      end

      expect(result.valid?).to be true
    end
  end
end
