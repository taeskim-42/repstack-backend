# frozen_string_literal: true

module Types
  class AiRoutineType < Types::BaseObject
    description "AI-generated workout routine with infinite variations"

    field :routine_id, String, null: false, description: "Unique routine identifier"
    field :generated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :user_level, Integer, null: false, description: "User's numeric level (1-8)"
    field :tier, String, null: false, description: "Level tier (beginner/intermediate/advanced)"
    field :day_of_week, String, null: false
    field :day_korean, String, null: false
    field :fitness_factor, String, null: false, description: "Today's fitness factor"
    field :fitness_factor_korean, String, null: false
    field :training_method, String, null: true
    field :training_method_info, Types::TrainingMethodInfoType, null: true
    field :condition, Types::ConditionStatusType, null: false
    field :estimated_duration_minutes, Integer, null: false
    field :exercises, [ Types::AiExerciseType ], null: false
    field :notes, [ String ], null: true

    # Resolvers to handle both Hash and WorkoutRoutine model objects
    def routine_id
      if object.is_a?(Hash)
        object[:routine_id] || object["routine_id"]
      else
        object.id.to_s
      end
    end

    def generated_at
      if object.is_a?(Hash)
        object[:generated_at] || object["generated_at"] || Time.current
      else
        object.generated_at || object.created_at
      end
    end

    def user_level
      if object.is_a?(Hash)
        object[:user_level] || object["user_level"] || 1
      else
        object.user&.user_profile&.numeric_level || 1
      end
    end

    def tier
      if object.is_a?(Hash)
        object[:tier] || object["tier"] || "beginner"
      else
        object.level || "beginner"
      end
    end

    def day_of_week
      if object.is_a?(Hash)
        object[:day_of_week] || object["day_of_week"] || "monday"
      else
        object.day_of_week || "monday"
      end
    end

    def day_korean
      if object.is_a?(Hash)
        object[:day_korean] || object["day_korean"] || "월요일"
      else
        day_names = %w[일요일 월요일 화요일 수요일 목요일 금요일 토요일]
        day_index = object.day_number || 1
        day_names[day_index] || "월요일"
      end
    end

    def fitness_factor
      if object.is_a?(Hash)
        object[:fitness_factor] || object["fitness_factor"] || "strength"
      else
        object.workout_type || "strength"
      end
    end

    def fitness_factor_korean
      if object.is_a?(Hash)
        object[:fitness_factor_korean] || object["fitness_factor_korean"] || "근력"
      else
        object.workout_type || "근력"
      end
    end

    def condition
      if object.is_a?(Hash)
        object[:condition] || object["condition"] || default_condition
      else
        default_condition
      end
    end

    def estimated_duration_minutes
      if object.is_a?(Hash)
        object[:estimated_duration_minutes] || object["estimated_duration_minutes"] || 45
      else
        object.estimated_duration || 45
      end
    end

    def exercises
      if object.is_a?(Hash)
        object[:exercises] || object["exercises"] || []
      else
        object.routine_exercises.order(:order_index).map do |ex|
          {
            exercise_id: ex.id.to_s,
            exercise_name: ex.exercise_name,
            target_muscle: ex.target_muscle,
            order: ex.order_index,
            sets: ex.sets,
            reps: ex.reps,
            rest_seconds: ex.rest_duration_seconds,
            instructions: ex.how_to,
            weight_description: ex.weight_description
          }
        end
      end
    end

    def notes
      if object.is_a?(Hash)
        object[:notes] || object["notes"]
      else
        nil
      end
    end

    def training_method
      if object.is_a?(Hash)
        object[:training_method] || object["training_method"]
      else
        object.workout_type
      end
    end

    def training_method_info
      if object.is_a?(Hash)
        object[:training_method_info] || object["training_method_info"]
      else
        nil
      end
    end

    private

    def default_condition
      { score: 3.0, status: "양호", intensity_modifier: 1.0, volume_modifier: 1.0 }
    end
  end
end
