class AddAppleRefreshTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :apple_refresh_token, :string
  end
end
