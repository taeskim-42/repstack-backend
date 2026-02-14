# frozen_string_literal: true

module Webhooks
  class AppStoreController < ApplicationController
    skip_before_action :authorize_request

    # POST /webhooks/app_store
    # Handles App Store Server Notification v2
    # https://developer.apple.com/documentation/appstoreservernotifications
    def create
      payload = parse_signed_payload
      unless payload
        render json: { error: "Invalid payload" }, status: :bad_request
        return
      end

      notification_type = payload["notificationType"]
      subtype = payload["subtype"]
      transaction_info = extract_transaction_info(payload)

      unless transaction_info
        Rails.logger.warn("AppStore webhook: missing transaction info for #{notification_type}")
        head :ok
        return
      end

      process_notification(notification_type, subtype, transaction_info)
      head :ok
    rescue StandardError => e
      Rails.logger.error("AppStore webhook error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      head :ok
    end

    private

    def skip_authentication?
      true
    end

    def parse_signed_payload
      body = request.body.read
      data = JSON.parse(body)

      # In production, verify the JWS signed payload using Apple's certificates
      # For now, decode the JWT payload without verification for sandbox testing
      signed_payload = data["signedPayload"]
      return nil unless signed_payload

      # JWT has 3 parts: header.payload.signature
      parts = signed_payload.split(".")
      return nil unless parts.length == 3

      decoded = Base64.urlsafe_decode64(parts[1] + "=" * (4 - parts[1].length % 4))
      JSON.parse(decoded)
    rescue JSON::ParserError, ArgumentError => e
      Rails.logger.error("AppStore webhook parse error: #{e.message}")
      nil
    end

    def extract_transaction_info(payload)
      signed_transaction = payload.dig("data", "signedTransactionInfo")
      return nil unless signed_transaction

      parts = signed_transaction.split(".")
      return nil unless parts.length == 3

      decoded = Base64.urlsafe_decode64(parts[1] + "=" * (4 - parts[1].length % 4))
      JSON.parse(decoded)
    rescue JSON::ParserError, ArgumentError => e
      Rails.logger.error("AppStore webhook transaction parse error: #{e.message}")
      nil
    end

    def process_notification(type, subtype, transaction)
      original_transaction_id = transaction["originalTransactionId"]
      product_id = transaction["productId"]
      expires_date = transaction["expiresDate"]

      subscription = Subscription.find_by(original_transaction_id: original_transaction_id)

      case type
      when "SUBSCRIBED"
        handle_subscribed(subscription, transaction)
      when "DID_RENEW"
        handle_renewed(subscription, expires_date)
      when "DID_FAIL_TO_RENEW"
        handle_billing_retry(subscription, subtype)
      when "EXPIRED"
        handle_expired(subscription)
      when "GRACE_PERIOD_EXPIRED"
        handle_expired(subscription)
      when "REVOKE"
        handle_revoked(subscription)
      when "REFUND"
        handle_revoked(subscription)
      else
        Rails.logger.info("AppStore webhook: unhandled notification type=#{type} subtype=#{subtype}")
      end
    end

    def handle_subscribed(subscription, transaction)
      return unless subscription

      expires_at = transaction["expiresDate"] ? Time.at(transaction["expiresDate"] / 1000) : nil
      subscription.update!(status: "active", expires_at: expires_at)
      Rails.logger.info("AppStore: subscription activated id=#{subscription.id}")
    end

    def handle_renewed(subscription, expires_date)
      return unless subscription

      expires_at = expires_date ? Time.at(expires_date / 1000) : nil
      subscription.update!(status: "active", expires_at: expires_at)
      Rails.logger.info("AppStore: subscription renewed id=#{subscription.id}")
    end

    def handle_billing_retry(subscription, subtype)
      return unless subscription

      new_status = subtype == "GRACE_PERIOD" ? "grace_period" : "billing_retry_period"
      subscription.update!(status: new_status)
      Rails.logger.info("AppStore: subscription billing retry id=#{subscription.id} status=#{new_status}")
    end

    def handle_expired(subscription)
      return unless subscription

      subscription.update!(status: "expired")
      Rails.logger.info("AppStore: subscription expired id=#{subscription.id}")
    end

    def handle_revoked(subscription)
      return unless subscription

      subscription.update!(status: "revoked")
      Rails.logger.info("AppStore: subscription revoked id=#{subscription.id}")
    end
  end
end
