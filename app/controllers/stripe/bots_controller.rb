# frozen_string_literal: true

require "stripe"

class Stripe::BotsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  skip_before_action :masquerade_user!
  before_action :verify_stripe_signature

  def create
    payload = request.body.read
    sig_header = request.headers["Stripe-Signature"]
    event = nil

    begin
      # Use the webhook secret from verify_stripe_signature (already validated)
      webhook_secret = @webhook_secret
      event = Stripe::Webhook.construct_event(payload, sig_header, webhook_secret) if webhook_secret
    rescue JSON::ParserError => e
      Rails.logger.error "Stripe webhook: Invalid JSON payload: #{e.message}"
      head :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe webhook: Signature verification failed: #{e.message}"
      head :forbidden
      return
    rescue StandardError => e
      Rails.logger.error "Stripe webhook: Error processing webhook: #{e.message}"
      head :bad_request
      return
    end

    # Idempotency: Check if this event has already been processed
    event_id = event.id
    cache_key = "stripe_webhook_processed_#{event_id}"

    if Rails.cache.exist?(cache_key)
      Rails.logger.info "Stripe webhook: Event #{event_id} (#{event.type}) already processed, skipping"
      head :ok
      return
    end

    # Handle subscription state changes
    case event.type
    when "customer.subscription.created", "customer.subscription.updated"
      handle_subscription_update(event.data.object)
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "invoice.paid", "invoice.payment_succeeded"
      handle_invoice_paid(event.data.object)
    else
      Rails.logger.info "Stripe webhook: Unhandled event type: #{event.type}"
    end

    # Mark event as processed (24 hour TTL - Stripe events are immutable)
    # This prevents duplicate processing if Stripe retries the webhook
    Rails.cache.write(cache_key, true, expires_in: 24.hours)

    head :ok
  end

  private

  def verify_stripe_signature
    signing_secrets = Rails.application.credentials.dig(:stripe, :signing_secret)

    if signing_secrets.blank?
      Rails.logger.error "SECURITY: Stripe webhook signing_secret not configured in credentials!"
      head :forbidden
      return
    end

    @webhook_secret = signing_secrets.is_a?(Array) ? signing_secrets.first : signing_secrets
  end

  def handle_subscription_update(subscription)
    # Check if subscription is actually active
    return unless subscription.status == "active"

    # Get Telegram user ID from subscription metadata
    telegram_user_id = subscription.metadata["telegram_user_id"]

    # If not in subscription metadata, try to get from customer metadata
    if telegram_user_id.blank?
      customer_id = subscription.customer.is_a?(Stripe::Customer) ? subscription.customer.id : subscription.customer
      customer = Stripe::Customer.retrieve(customer_id) if customer_id
      telegram_user_id = customer.metadata["telegram_user_id"] if customer
    end

    return unless telegram_user_id

    # Find which bot integration this subscription belongs to by price ID
    price_id = subscription.items.data.first&.price&.id
    return unless price_id

    bot_integration = TelegramBotIntegration.active.find do |bot|
      bot.stripe_price_ids.include?(price_id)
    end

    return unless bot_integration

    # Grant access to Telegram channel
    grant_channel_access(bot_integration, telegram_user_id)
  end

  def handle_checkout_completed(checkout_session)
    # Handle one-time payments
    return unless checkout_session.mode == "payment" && checkout_session.payment_status == "paid"

    telegram_user_id = checkout_session.metadata["telegram_user_id"]
    telegram_chat_id = checkout_session.metadata["telegram_chat_id"]
    return unless telegram_user_id

    # Find bot integration by price ID from checkout session
    line_items = Stripe::Checkout::Session.list_line_items(checkout_session.id)
    return if line_items.data.empty?

    price_id = line_items.data.first.price.id
    return unless price_id

    bot_integration = TelegramBotIntegration.active.find do |bot|
      bot.stripe_price_ids.include?(price_id)
    end

    return unless bot_integration

    # Grant access for one-time payment (use chat_id for sending messages)
    grant_channel_access(bot_integration, telegram_user_id, telegram_chat_id)
  end

  def handle_invoice_paid(invoice)
    # Handle invoice.paid and invoice.payment_succeeded events
    # These fire when a subscription invoice is paid (including the first one)
    return unless invoice.paid

    # Get Telegram user ID and chat ID from invoice metadata (from subscription_details)
    telegram_user_id = invoice.subscription_details&.metadata&.[]("telegram_user_id") ||
                       invoice.metadata["telegram_user_id"] ||
                       invoice.lines&.data&.first&.metadata&.[]("telegram_user_id")

    telegram_chat_id = invoice.subscription_details&.metadata&.[]("telegram_chat_id") ||
                       invoice.metadata["telegram_chat_id"] ||
                       invoice.lines&.data&.first&.metadata&.[]("telegram_chat_id")

    return unless telegram_user_id

    # Get subscription ID from invoice
    subscription_id = invoice.subscription
    return unless subscription_id

    # Retrieve subscription to check status and get price
    subscription = Stripe::Subscription.retrieve(subscription_id)
    return unless subscription.status == "active"

    # If chat_id still not found, try subscription metadata
    telegram_chat_id ||= subscription.metadata["telegram_chat_id"]

    # Get price ID from subscription
    price_id = subscription.items.data.first&.price&.id
    return unless price_id

    # Find bot integration by price ID
    bot_integration = TelegramBotIntegration.active.find do |bot|
      bot.stripe_price_ids.include?(price_id)
    end

    return unless bot_integration

    # Grant access when invoice is paid
    grant_channel_access(bot_integration, telegram_user_id, telegram_chat_id)
  end

  def grant_channel_access(bot_integration, telegram_user_id, telegram_chat_id = nil)
    telegram_service = TelegramBotIntegrationService.new(bot_integration)
    locale = bot_integration.default_language.to_sym

    # Use chat_id for sending messages (fallback to user_id if chat_id not provided)
    # In private chats, chat_id == user_id, but chat_id is more reliable
    chat_id_for_messages = telegram_chat_id&.to_i || telegram_user_id.to_i
    user_id_for_channel = telegram_user_id.to_i

    # Try to add user directly to channel
    result = telegram_service.invite_user_to_channel(telegram_user_id: user_id_for_channel)

    I18n.with_locale(locale) do
      # Check if user is already a member
      is_member = telegram_service.check_channel_membership(telegram_user_id: user_id_for_channel)

      if is_member
        # User already has access - send confirmation message with channel link
        channel_link = telegram_service.get_channel_invite_link
        reply_markup = if channel_link
                         {
                           inline_keyboard: [ [
                             { text: I18n.t("bot.step5_status.button_open_channel"), url: channel_link }
                           ] ]
                         }
        else
                         nil
        end

        telegram_service.send_message(
          chat_id: chat_id_for_messages,
          text: I18n.t("bot.step4_payment_success.message_already_member"),
          reply_markup: reply_markup
        )
        return
      end

      if result && result.is_a?(Hash) && result["ok"]
        # Successfully added directly
        telegram_service.send_message(
          chat_id: chat_id_for_messages,
          text: I18n.t("bot.step4_payment_success.message_added_directly")
        )
      else
        # Failed to add directly - provide invite link
        invite_link = telegram_service.get_channel_invite_link

        if invite_link
          reply_markup = {
            inline_keyboard: [ [
              { text: I18n.t("bot.step4_payment_success.button_join_channel"), url: invite_link }
            ] ]
          }

          telegram_service.send_message(
            chat_id: chat_id_for_messages,
            text: I18n.t("bot.step4_payment_success.message_invite_link"),
            reply_markup: reply_markup
          )
        else
          # Could not get invite link - ask to contact support
          telegram_service.send_message(
            chat_id: chat_id_for_messages,
            text: I18n.t("bot.step4_payment_success.message_contact_support")
          )
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to grant channel access: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end
end
