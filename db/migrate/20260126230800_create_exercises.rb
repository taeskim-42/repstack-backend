# frozen_string_literal: true

class CreateExercises < ActiveRecord::Migration[7.2]
  def change
    create_table :exercises do |t|
      # Basic info
      t.string :name, null: false                    # Korean name (푸시업)
      t.string :english_name, null: false            # English name (push_up)
      t.string :display_name                         # Display name with variant (BPM 푸시업)

      # Categorization
      t.string :muscle_group, null: false            # chest, back, legs, shoulders, arms, core, cardio
      t.string :secondary_muscles, array: true, default: []  # Additional muscles worked
      t.string :movement_pattern                     # push, pull, squat, hinge, carry, rotation

      # Fitness factors this exercise trains
      t.string :fitness_factors, array: true, default: []    # strength, muscular_endurance, power, cardiovascular

      # Requirements
      t.string :equipment, array: true, default: []  # none, barbell, dumbbell, cable, machine, pull_up_bar, etc.
      t.integer :difficulty, default: 1              # 1-5 scale
      t.integer :min_level, default: 1               # Minimum user level required

      # Training method compatibility
      t.boolean :bpm_compatible, default: true       # Can be done with metronome
      t.boolean :tabata_compatible, default: true    # Suitable for tabata intervals
      t.boolean :dropset_compatible, default: false  # Can be done as dropset
      t.boolean :superset_compatible, default: true  # Can be paired in superset

      # ROM options available
      t.string :rom_options, array: true, default: ['full']  # full, medium, short

      # Instructions
      t.text :description                            # General description
      t.text :form_tips                              # Form/technique tips
      t.text :common_mistakes                        # Common mistakes to avoid
      t.jsonb :variations, default: {}               # Exercise variations

      # Metadata
      t.boolean :active, default: true
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :exercises, :name, unique: true
    add_index :exercises, :english_name, unique: true
    add_index :exercises, :muscle_group
    add_index :exercises, :difficulty
    add_index :exercises, :fitness_factors, using: :gin
    add_index :exercises, :equipment, using: :gin
    add_index :exercises, :active
  end
end
