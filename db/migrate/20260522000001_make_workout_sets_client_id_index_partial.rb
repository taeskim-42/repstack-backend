# frozen_string_literal: true

# Convert UNIQUE index on workout_sets(client_id) from global to partial
# (WHERE client_id IS NOT NULL).
#
# Why: legacy rows have NULL client_id. PostgreSQL UNIQUE treats NULLs as
# distinct so the current index already permits them, but a partial form is
# explicit, smaller on disk, and consistent with R6-R16 design consensus.
# It also enables the `rescue ActiveRecord::RecordNotUnique` race close in
# Mutations::AddWorkoutSet without surprises for legacy rows.
#
# Uses CONCURRENTLY to avoid blocking writes on workout_sets.
class MakeWorkoutSetsClientIdIndexPartial < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :workout_sets,
                 name: "index_workout_sets_on_client_id",
                 algorithm: :concurrently,
                 if_exists: true

    add_index :workout_sets,
              :client_id,
              unique: true,
              where: "client_id IS NOT NULL",
              name: "index_workout_sets_on_client_id",
              algorithm: :concurrently
  end

  def down
    remove_index :workout_sets,
                 name: "index_workout_sets_on_client_id",
                 algorithm: :concurrently,
                 if_exists: true

    add_index :workout_sets,
              :client_id,
              unique: true,
              name: "index_workout_sets_on_client_id",
              algorithm: :concurrently
  end
end
