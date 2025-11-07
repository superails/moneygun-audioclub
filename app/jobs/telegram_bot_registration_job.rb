# frozen_string_literal: true

class TelegramBotRegistrationJob < ApplicationJob
  queue_as :default

  def perform(bot_integration_id)
    bot = TelegramBotIntegration.find_by(id: bot_integration_id)
    return unless bot&.active?

    service = TelegramBotIntegrationService.new(bot)

    # 1. Set bot commands for all languages
    Rails.logger.info "Registering commands for bot integration #{bot_integration_id}"
    service.set_commands(set_for_all_languages: true)

    # 2. Set webhook URL
    webhook_url = build_webhook_url(bot.telegram_webhook_token)
    Rails.logger.info "Setting webhook for bot integration #{bot_integration_id} to #{webhook_url}"

    webhook_result = service.set_webhook(
      url: webhook_url,
      secret_token: bot.telegram_webhook_token
    )

    if webhook_result && webhook_result["ok"]
      Rails.logger.info "Successfully registered bot #{bot_integration_id} with Telegram"
    else
      Rails.logger.error "Failed to register bot #{bot_integration_id}: #{webhook_result.inspect}"
    end
  rescue StandardError => e
    Rails.logger.error "Error in TelegramBotRegistrationJob for bot #{bot_integration_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    raise # Re-raise to trigger retry mechanism
  end

  private

  def build_webhook_url(_webhook_token)
    base_url = ENV.fetch("RAILS_HOST", "localhost:3000")
    base_url = base_url.split(":").first if base_url.include?(":")

    "https://#{base_url}/telegram/bots/webhooks"
  end
end
