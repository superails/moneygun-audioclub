# frozen_string_literal: true

# TelegramBotIntegration.all.each { |bot| bot.register_bot_with_telegram }

class TelegramBotIntegration < ApplicationRecord
  # Encryption
  encrypts :telegram_bot_token if Rails.application.credentials.active_record_encryption.present?
  encrypts :telegram_webhook_token, deterministic: true if Rails.application.credentials.active_record_encryption.present?

  # Validations
  validates :name, presence: true
  validates :telegram_bot_token, presence: true, uniqueness: true
  validates :telegram_webhook_token, presence: true, uniqueness: true
  validates :telegram_chat_id, presence: true
  validates :telegram_bot_username, format: { with: /\A[a-zA-Z0-9_]{5,32}\z/, message: "must be a valid Telegram bot username (5-32 alphanumeric characters or underscores)" }, allow_blank: true
  validates :stripe_price_ids, presence: true
  validates :offer_message, presence: true
  validates :default_language, inclusion: { in: %w[en uk ru] }

  # Callbacks
  before_validation :generate_webhook_token, on: :create
  before_validation :normalize_stripe_price_ids
  before_validation :fetch_bot_username, on: :create, if: -> { telegram_bot_token.present? && telegram_bot_username.blank? }
  after_commit :register_bot_with_telegram, on: %i[create update], if: -> { active? }

  # Scopes
  scope :active, -> { where(active: true) }

  # Find bot by webhook token (for webhook routing)
  def self.find_by_webhook_token(token)
    active.find_by(telegram_webhook_token: token)
  end

  # Get locale for this bot (default or detect from message)
  def locale_for_message(message = nil)
    return default_language.to_sym unless message

    from_data = message["from"] || message[:from]
    return default_language.to_sym unless from_data

    lang_code = (from_data["language_code"] || from_data[:language_code])&.downcase
    return default_language.to_sym unless lang_code

    case lang_code
    when "en", "en-us", "en-gb"
      :en
    when "uk", "uk-ua"
      :uk
    when "ru", "ru-ru"
      :ru
    else
      default_language.to_sym
    end
  end

  def normalize_stripe_price_ids
    return if stripe_price_ids.blank?

    if stripe_price_ids.is_a?(String)
      # Handle newline or comma-separated strings
      normalized = stripe_price_ids.split(/[\n,]/).map(&:strip).reject(&:blank?)
      self.stripe_price_ids = normalized
    elsif stripe_price_ids.is_a?(Array)
      self.stripe_price_ids = stripe_price_ids.reject(&:blank?)
    end
  end

  def generate_webhook_token
    return if telegram_webhook_token.present?

    loop do
      self.telegram_webhook_token = SecureRandom.alphanumeric(32)
      break unless self.class.exists?(telegram_webhook_token: telegram_webhook_token)
    end
  end

  def fetch_bot_username
    return if telegram_bot_token.blank?

    service = TelegramBotIntegrationService.new(self)
    username = service.bot_username

    if username.present?
      self.telegram_bot_username = username
    else
      Rails.logger.warn "Failed to fetch bot username from Telegram API for bot integration #{id || 'new'}"
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching bot username: #{e.message}"
  end

  def register_bot_with_telegram
    return if telegram_bot_token.blank? || telegram_webhook_token.blank? || id.blank?

    TelegramBotRegistrationJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error "Failed to schedule bot registration: #{e.message}"
  end
end
