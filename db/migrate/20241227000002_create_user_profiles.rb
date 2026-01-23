class CreateUserProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :user_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :height, precision: 5, scale: 2
      t.decimal :weight, precision: 5, scale: 2
      t.decimal :body_fat_percentage, precision: 5, scale: 2
      t.string :current_level
      t.integer :week_number, default: 1
      t.integer :day_number, default: 1
      t.string :fitness_goal
      t.date :program_start_date

      t.timestamps
    end

    add_index :user_profiles, :user_id, unique: true
  end
end
