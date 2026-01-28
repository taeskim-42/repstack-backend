class AddLanguageToYoutubeChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :youtube_channels, :language, :string, default: "ko", null: false
    add_index :youtube_channels, :language
  end
end
