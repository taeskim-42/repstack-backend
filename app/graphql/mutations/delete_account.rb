# frozen_string_literal: true

module Mutations
  class DeleteAccount < BaseMutation
    description "Permanently delete user account and all associated data"

    argument :confirmation, String, required: true,
      description: 'Must be "DELETE" to confirm account deletion'

    field :success, Boolean, null: false
    field :errors, [String], null: false

    def resolve(confirmation:)
      user = authenticate!

      unless confirmation == "DELETE"
        return { success: false, errors: ["확인을 위해 'DELETE'를 입력해주세요."] }
      end

      revoke_apple_token(user) if user.apple_user?
      UserDataDeleter.delete_all_for(user)
      User.where(id: user.id).delete_all

      Rails.logger.info("[DeleteAccount] Successfully deleted user #{user.id} (#{user.email})")
      { success: true, errors: [] }
    rescue StandardError => e
      Rails.logger.error("[DeleteAccount] Failed for user #{user.id}: #{e.class} - #{e.message}")
      { success: false, errors: ["계정 삭제에 실패했습니다. 다시 시도해주세요."] }
    end

    private

    def revoke_apple_token(user)
      return unless user.apple_refresh_token.present?

      AppleTokenService.revoke_token(user.apple_refresh_token)
    rescue StandardError => e
      # Best-effort: don't block deletion if revocation fails
      Rails.logger.warn("Apple token revocation failed for user #{user.id}: #{e.message}")
    end
  end
end
