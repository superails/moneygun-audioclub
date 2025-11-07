# frozen_string_literal: true

require "faraday"

# Service for making Telegram API calls using a specific bot integration's token
class TelegramBotIntegrationService
  BASE_URL = "https://api.telegram.org/bot"

  def initialize(bot_integration)
    @bot_integration = bot_integration
    @bot_token = bot_integration.telegram_bot_token
    @chat_id = bot_integration.telegram_chat_id
    raise "Bot token not configured" if @bot_token.blank?

    @conn = Faraday.new(url: "#{BASE_URL}#{@bot_token}") do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
    end
  end

  # Get bot info from Telegram API
  def get_bot_info
    response = _make_request("getMe", {}, http_method: :get)
    return nil unless response && response["ok"]

    response["result"]
  end

  # Get bot username from Telegram API
  def bot_username
    bot_info = get_bot_info
    bot_info&.dig("username")
  end

  def send_message(chat_id:, text:, parse_mode: "HTML", reply_markup: nil)
    params = {
      chat_id: chat_id,
      text: text,
      parse_mode: parse_mode
    }

    params[:reply_markup] = reply_markup if reply_markup

    _make_request("sendMessage", params)
  end

  def invite_user_to_channel(telegram_user_id:)
    return false if @chat_id.blank?

    # Try addChatMember first (newer API), fallback to inviteChatMember if needed
    result = _make_request("addChatMember", {
                             chat_id: @chat_id,
                             user_id: telegram_user_id
                           })

    # If addChatMember fails, try inviteChatMember (legacy)
    if !result || result == false || (result.is_a?(Hash) && !result["ok"])
      Rails.logger.warn "addChatMember failed, trying inviteChatMember: #{result.inspect}"
      result = _make_request("inviteChatMember", {
                               chat_id: @chat_id,
                               user_id: telegram_user_id,
                               can_read_messages: true
                             })
    end

    result
  end

  def check_channel_membership(telegram_user_id:)
    return false if @chat_id.blank?

    response = _make_request("getChatMember", {
                               chat_id: @chat_id,
                               user_id: telegram_user_id
                             }, http_method: :post)

    return false unless response && response["ok"]

    status = response.dig("result", "status")
    %w[creator administrator member restricted].include?(status)
  end

  def get_channel_invite_link
    return nil if @chat_id.blank?

    # Try to get channel info to check if it has a username
    chat_info = _make_request("getChat", {
                                chat_id: @chat_id
                              }, http_method: :post)

    return nil unless chat_info.is_a?(Hash) && chat_info["ok"]

    chat = chat_info["result"]
    return nil unless chat.is_a?(Hash)

    username = chat["username"]

    # If channel has a username, use it (permanent link)
    return "https://t.me/#{username}" if username.present?

    # For channels without username, create a new invite link
    invite_link_response = create_fresh_invite_link

    return nil unless invite_link_response.is_a?(Hash) && invite_link_response["ok"]

    invite_link = invite_link_response.dig("result", "invite_link") || invite_link_response["result"]
    invite_link.is_a?(String) ? invite_link : nil
  end

  def create_fresh_invite_link
    _make_request("createChatInviteLink", {
                    chat_id: @chat_id,
                    creates_join_request: false,
                    name: "Subscription Access Link"
                  }, http_method: :post)
  rescue StandardError => e
    Rails.logger.warn "Failed to create fresh invite link: #{e.message}. Trying exportChatInviteLink as fallback."

    _make_request("exportChatInviteLink", {
                    chat_id: @chat_id
                  }, http_method: :post)
  end

  def answer_callback_query(callback_query_id, text: nil, show_alert: false)
    params = { callback_query_id: callback_query_id }
    params[:text] = text if text
    params[:show_alert] = show_alert if show_alert
    _make_request("answerCallbackQuery", params)
  end

  def edit_message_text(chat_id:, message_id:, text:, parse_mode: "HTML", reply_markup: nil)
    params = {
      chat_id: chat_id,
      message_id: message_id,
      text: text,
      parse_mode: parse_mode
    }
    params[:reply_markup] = reply_markup if reply_markup
    _make_request("editMessageText", params)
  end

  def delete_message(chat_id:, message_id:)
    _make_request("deleteMessage", {
                    chat_id: chat_id,
                    message_id: message_id
                  })
  end

  # Set webhook URL for the bot
  def set_webhook(url:, secret_token: nil)
    params = { url: url }
    params[:secret_token] = secret_token if secret_token.present?
    _make_request("setWebhook", params)
  end

  # Set bot commands (for command menu)
  # Supports setting commands for multiple languages
  def set_commands(commands = nil, language_code: nil, set_for_all_languages: false)
    # Default commands
    commands ||= [
      { command: "start", description: "Start the bot and subscribe" },
      { command: "status", description: "Check subscription status and manage account" },
      { command: "cancel", description: "Cancel current operation" }
    ]

    # Convert to Telegram API format
    commands_json = commands.map do |cmd|
      {
        "command" => cmd[:command] || cmd["command"],
        "description" => cmd[:description] || cmd["description"]
      }
    end

    # Set scope to "all_private_chats" to ensure commands appear in direct messages
    scope = { type: "all_private_chats" }

    # If set_for_all_languages is true, set commands for all supported languages
    if set_for_all_languages
      results = []
      %w[en uk ru].each do |lang|
        params = { commands: commands_json, language_code: lang, scope: scope }
        result = _make_request("setMyCommands", params)
        results << { language: lang, result: result }
        Rails.logger.info "Set #{commands_json.length} commands for language: #{lang}" if result && result["ok"]
      end
      # Also set default (no language code) for fallback
      params = { commands: commands_json, scope: scope }
      result = _make_request("setMyCommands", params)
      results << { language: "default", result: result }
      Rails.logger.info "Set #{commands_json.length} commands for default language" if result && result["ok"]
      return results
    end

    # Set for specific language or default
    params = { commands: commands_json, scope: scope }
    params[:language_code] = language_code if language_code

    result = _make_request("setMyCommands", params)

    if result && result["ok"]
      Rails.logger.info "Successfully set #{commands_json.length} commands#{" for language #{language_code}" if language_code}"
    end

    result
  end

  # Get current webhook info
  def get_webhook_info
    _make_request("getWebhookInfo", {}, http_method: :get)
  end

  private

  def _make_request(method, params = {}, http_method: :post)
    response = @conn.public_send(http_method, method) do |req|
      req.body = params if http_method == :post
      req.params = params if http_method == :get && params.any?
    end

    if response.status == 200
      response.body
    else
      Rails.logger.error "Telegram API error for bot #{@bot_integration.id}: #{response.body.inspect}"
      false
    end
  rescue Faraday::Error, StandardError => e
    Rails.logger.error "Telegram API exception for bot #{@bot_integration.id}: #{e.message}"
    false
  end
end
