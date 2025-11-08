# frozen_string_literal: true

class Telegram::BotsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  skip_before_action :masquerade_user!
  before_action :identify_bot
  before_action :validate_chat_and_user

  def create
    update = params[:webhook] || params
    message = update[:message]
    callback_query = update[:callback_query]

    if message.present? && message["text"]
      # Check if user is waiting for price selection
      waiting_state = Rails.cache.read("bot_waiting_price_#{chat_id}")

      if waiting_state && waiting_state.is_a?(Hash) && waiting_state[:telegram_user_id] == telegram_user_id
        handle_price_response(message, waiting_state)
      else
        case message["text"]
        when "/start"
          handle_start_command(message)
        when "/status"
          handle_status_command(message)
        when "/cancel"
          handle_cancel_command(message)
        end
      end
    elsif callback_query.present?
      handle_callback_query(callback_query)
    end

    head :ok
  end

  private

  attr_reader :bot_integration, :telegram_service, :stripe_service, :chat_id, :telegram_user_id

  # Identify bot by matching webhook token from header
  def identify_bot
    provided_token = request.headers["X-Telegram-Bot-Api-Secret-Token"]

    unless provided_token.present?
      Rails.logger.warn "Telegram bot webhook: No secret token provided"
      head :forbidden
      return
    end

    @bot_integration = TelegramBotIntegration.find_by_webhook_token(provided_token)

    unless @bot_integration
      Rails.logger.warn "Telegram bot webhook: Bot not found for token"
      head :forbidden
      return
    end

    @telegram_service = TelegramBotIntegrationService.new(@bot_integration)
    @stripe_service = StripeBotService.new
  end

  def validate_chat_and_user
    update = params[:webhook] || params
    message = update[:message] || update[:callback_query]&.dig("message")

    return head(:bad_request) unless message

    @chat_id = message.dig("chat", "id")&.to_i
    @telegram_user_id = message.dig("from", "id")&.to_i

    return unless @chat_id.nil? || @telegram_user_id.nil?

    Rails.logger.warn "Telegram bot webhook: Invalid chat_id or telegram_user_id"
    head :bad_request
  end

  def locale
    @locale ||= begin
      update = params[:webhook] || params
      message = update[:message] || update[:callback_query]&.dig("message")
      @bot_integration.locale_for_message(message)
    end
  end

  def t_bot(key, **)
    I18n.t("bot.#{key}", **)
  end

  def handle_start_command(_message)
    locale_value = locale

    I18n.with_locale(locale_value) do
      # Show customizable offer message with buttons
      reply_markup = {
        inline_keyboard: [ [
          { text: t_bot("step1_offer.button_get_started"), callback_data: "get_started" },
          { text: t_bot("step1_offer.button_maybe_later"), callback_data: "maybe_later" }
        ] ]
      }

      telegram_service.send_message(
        chat_id: chat_id,
        text: bot_integration.offer_message,
        reply_markup: reply_markup
      )
    end
  end

  def handle_callback_query(callback_query)
    callback_data = callback_query["data"]
    locale_value = locale

    # Answer callback to stop loading animation
    telegram_service.answer_callback_query(callback_query["id"])

    I18n.with_locale(locale_value) do
      case callback_data
      when "get_started"
        handle_show_plans(callback_query)
      when "maybe_later"
        telegram_service.send_message(
          chat_id: chat_id,
          text: t_bot("step1_offer.response_not_ready")
        )
      when /^price_(.+)$/
        price_id = Regexp.last_match(1)
        handle_price_selection(callback_query, price_id)
      else
        Rails.logger.warn "Unknown callback_data: #{callback_data}"
      end
    end
  end

  def handle_show_plans(_callback_query = nil)
    # Fetch prices from Stripe API
    price_ids = bot_integration.stripe_price_ids
    prices = stripe_service.fetch_prices(price_ids)

    if prices.empty?
      telegram_service.send_message(
        chat_id: chat_id,
        text: t_bot("step2_plans.error_none_available")
      )
      return
    end

    # Build plan selection message with buttons
    plan_text = "#{t_bot('step2_plans.title')}\n\n"

    inline_keyboard = []

    prices.each do |price|
      amount = format_price_amount(price)
      currency_symbol = format_currency_symbol(price.currency)
      interval = format_price_interval(price)

      plan_text += "#{currency_symbol}#{amount} - #{interval}\n"
      inline_keyboard << [ { text: "#{currency_symbol}#{amount} - #{interval}", callback_data: "price_#{price.id}" } ]
    end

    telegram_service.send_message(
      chat_id: chat_id,
      text: plan_text,
      reply_markup: { inline_keyboard: inline_keyboard }
    )
  end

  def handle_price_selection(callback_query, price_id)
    # Show "Generating payment link..." message
    generating_msg = telegram_service.send_message(
      chat_id: chat_id,
      text: t_bot("step3_payment.message_generating")
    )

    begin
      # Get bot username from Telegram API (fallback to stored value if API fails)
      bot_username = telegram_service.bot_username || bot_integration.telegram_bot_username

      # Fetch price to check if it's recurring
      price = stripe_service.fetch_prices([ price_id ]).first
      is_recurring = price&.recurring.present?

      # Create Stripe checkout session
      checkout_url = stripe_service.create_checkout_session(
        price_id: price_id,
        telegram_user_id: telegram_user_id,
        telegram_chat_id: chat_id,
        bot_username: bot_username
      )

      unless checkout_url
        edit_generating_message(generating_msg, t_bot("step3_payment.error_generating"))
        return
      end

      # Get user account information
      user_info = callback_query&.dig("from") || {}
      username = user_info["username"]
      first_name = user_info["first_name"]
      last_name = user_info["last_name"]

      account_info = if username
        name_parts = [ first_name, last_name ].compact.join(" ")
        name_parts.empty? ? "@#{username}" : "@#{username} - #{name_parts}"
      else
        name_parts = [ first_name, last_name ].compact.join(" ")
        name_parts.empty? ? "User" : name_parts
      end

      # Replace "generating" message with payment terms and button
      # Only include unsubscribe note for recurring subscriptions
      unsubscribe_note = is_recurring ? t_bot("step2_plans.unsubscribe_note") : ""
      payment_text = t_bot("step3_payment.message_terms", account_info: account_info, unsubscribe_note: unsubscribe_note)

      reply_markup = {
        inline_keyboard: [ [
          { text: t_bot("step3_payment.button_complete"), url: checkout_url }
        ] ]
      }

      # Edit the generating message to replace it with payment terms
      edit_generating_message(generating_msg, payment_text, reply_markup)
    rescue StandardError => e
      Rails.logger.error "Failed to create checkout session: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      begin
        edit_generating_message(generating_msg, t_bot("errors.something_wrong"))
      rescue StandardError
        nil
      end
    end
  end

  def handle_price_response(_message, _waiting_state)
    # This method is not used in the new flow (price selection is via buttons)
    # But kept for potential future use
    Rails.logger.warn "handle_price_response called but price selection is handled via callback queries"
  end

  def handle_status_command(_message)
    locale_value = locale

    I18n.with_locale(locale_value) do
      status_info = stripe_service.get_subscription_status(telegram_user_id: telegram_user_id)

      inline_keyboard = []

      case status_info[:status]
      when :active
        text = t_bot("step5_status.message_active")
        # Add "Open Channel" button
        channel_link = telegram_service.get_channel_invite_link
        inline_keyboard << [ { text: t_bot("step5_status.button_open_channel"), url: channel_link } ] if channel_link
        # Add "Manage Subscription" button with billing portal link
        add_billing_portal_button(status_info, inline_keyboard)
      when :cancelled
        ends_at = status_info[:ends_at]
        formatted_date = ends_at ? Time.at(ends_at).strftime("%B %d, %Y") : t_bot("step5_status.ends_at_fallback")
        text = t_bot("step5_status.message_cancelled", ends_at: formatted_date)
        channel_link = telegram_service.get_channel_invite_link
        inline_keyboard << [ { text: t_bot("step5_status.button_open_channel"), url: channel_link } ] if channel_link
        # Add billing portal button for cancelled subscriptions too
        add_billing_portal_button(status_info, inline_keyboard)
      when :expiring
        ends_at = status_info[:ends_at]
        formatted_date = ends_at ? Time.at(ends_at).strftime("%B %d, %Y") : t_bot("step5_status.ends_at_fallback")
        text = t_bot("step5_status.message_expiring", ends_at: formatted_date)
        channel_link = telegram_service.get_channel_invite_link
        inline_keyboard << [ { text: t_bot("step5_status.button_open_channel"), url: channel_link } ] if channel_link
        # Add billing portal button for expiring subscriptions
        add_billing_portal_button(status_info, inline_keyboard)
      when :none
        text = t_bot("step5_status.message_none")
      else
        text = t_bot("step5_status.message_error")
      end

      reply_markup = inline_keyboard.any? ? { inline_keyboard: inline_keyboard } : nil

      telegram_service.send_message(
        chat_id: chat_id,
        text: text,
        reply_markup: reply_markup
      )
    rescue StandardError => e
      Rails.logger.error "Failed to get subscription status: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      telegram_service.send_message(
        chat_id: chat_id,
        text: t_bot("step5_status.message_error")
      )
    end
  end

  def add_billing_portal_button(status_info, inline_keyboard)
    return unless status_info[:customer]&.id

    # Get bot username for return URL
    bot_username = telegram_service.bot_username || bot_integration.telegram_bot_username
    return_url = if bot_username.present?
                   "https://t.me/#{bot_username}"
    else
                   "https://t.me"
    end

    # Create billing portal session
    portal_url = stripe_service.create_billing_portal_session(
      customer_id: status_info[:customer].id,
      return_url: return_url
    )

    # Add button if portal URL was created successfully
    inline_keyboard << [ { text: t_bot("step5_status.button_manage_subscription"), url: portal_url } ] if portal_url
  rescue StandardError => e
    Rails.logger.error "Failed to create billing portal button: #{e.message}"
    # Continue without the billing portal button
  end

  def handle_cancel_command(_message)
    locale_value = locale

    I18n.with_locale(locale_value) do
      # Clear any waiting states
      Rails.cache.delete("bot_waiting_price_#{chat_id}")

      telegram_service.send_message(
        chat_id: chat_id,
        text: t_bot("command_cancel.message")
      )
    end
  end

  def edit_generating_message(generating_msg, new_text, reply_markup = nil)
    return unless generating_msg.is_a?(Hash) && generating_msg["ok"]

    message_id = generating_msg.dig("result", "message_id")
    return unless message_id

    # Edit the generating message to replace it with the new content
    telegram_service.edit_message_text(
      chat_id: chat_id,
      message_id: message_id,
      text: new_text,
      reply_markup: reply_markup
    )
  rescue StandardError => e
    Rails.logger.error "Failed to edit generating message: #{e.message}"
    # Fallback: send as new message if editing fails
    telegram_service.send_message(
      chat_id: chat_id,
      text: new_text,
      reply_markup: reply_markup
    )
  end

  def format_price_amount(price)
    price.unit_amount / 100.0
  end

  def format_currency_symbol(currency)
    case currency.upcase
    when "USD" then "$"
    when "EUR" then "€"
    when "UAH" then "₴"
    when "RUB" then "₽"
    else currency.upcase
    end
  end

  def format_price_interval(price)
    return "one-time" unless price.recurring

    case price.recurring.interval
    when "month" then t_bot("step2_plans.interval_monthly")
    when "year" then t_bot("step2_plans.interval_yearly")
    else price.recurring.interval
    end
  end
end
