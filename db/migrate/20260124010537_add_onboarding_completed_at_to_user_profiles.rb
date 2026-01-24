class AddOnboardingCompletedAtToUserProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :onboarding_completed_at, :datetime
  end
end
