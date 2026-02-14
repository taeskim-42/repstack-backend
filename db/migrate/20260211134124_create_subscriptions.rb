class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :product_id, null: false
      t.string :original_transaction_id, null: false
      t.string :status, null: false, default: "active"
      t.datetime :expires_at
      t.datetime :purchased_at
      t.string :environment, default: "production"

      t.timestamps
    end

    add_index :subscriptions, :original_transaction_id, unique: true
    add_index :subscriptions, [:user_id, :status]
    add_index :subscriptions, :expires_at
  end
end
