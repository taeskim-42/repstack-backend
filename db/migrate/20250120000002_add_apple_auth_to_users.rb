# frozen_string_literal: true

class AddAppleAuthToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :apple_user_id, :string
    add_index :users, :apple_user_id, unique: true
    change_column_null :users, :password_digest, true
  end
end
