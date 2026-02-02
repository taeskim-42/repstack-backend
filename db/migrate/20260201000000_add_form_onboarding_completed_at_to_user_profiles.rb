# frozen_string_literal: true

class AddFormOnboardingCompletedAtToUserProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_profiles, :form_onboarding_completed_at, :datetime
  end
end
