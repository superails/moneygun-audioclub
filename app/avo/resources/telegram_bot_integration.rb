# frozen_string_literal: true

class Avo::Resources::TelegramBotIntegration < Avo::BaseResource
  self.title = :name
  self.includes = []
  self.search = {
    query: -> { query.ransack(id_eq: params[:q], name_cont: params[:q], m: "or").result(distinct: false) },
    item: lambda {
      {
        title: [ record.id, record.name ].join("/")
      }
    }
  }

  def fields
    main_panel do
      field :id, as: :id
      field :name, as: :text, required: true, help: "Admin-friendly name for this bot integration"
      field :active, as: :boolean, default: true, help: "Enable/disable this bot integration"

      # Show masked token on index/show, show actual value on edit/new
      field :telegram_bot_token, as: :textarea, required: true,
                                 help: "Telegram Bot API token from BotFather",
                                 format_using: lambda {
                                   # Only mask on index and show views
                                   if view.in?(%i[index show]) && value.present?
                                     "••••••••"
                                   else
                                     value
                                   end
                                 }

      # Webhook token is hidden from UI - auto-generated and auto-managed
      # field :telegram_webhook_token (intentionally hidden)

      field :telegram_chat_id, as: :text, required: true,
                               help: "Channel or group ID where users will be invited (can be negative)"

      field :telegram_bot_username, as: :text, required: false,
                                    help: "Bot username (without @) for return URLs. Auto-fetched from Telegram API if left blank. Example: 'my_bot' for @my_bot",
                                    hide_on: :new,
                                    disabled: true,
                                    format_using: -> { value.presence || "(will be auto-fetched from Telegram API)" }

      field :stripe_price_ids, as: :textarea, required: true,
                               help: "List of Stripe Price IDs (one per line or comma-separated). Both subscription and one-time prices supported.",
                               format_using: lambda {
                                 if value.is_a?(Array)
                                   value.join("\n")
                                 elsif value.is_a?(String)
                                   value
                                 else
                                   ""
                                 end
                               },
                               rows: 5

      field :default_language, as: :select,
                               options: { English: "en", Ukrainian: "uk", Russian: "ru" },
                               default: "en",
                               help: "Default language for bot messages if user's language is not detected"

      field :offer_message, as: :textarea, required: true,
                            help: "Custom offer description shown in /start command. Use HTML for formatting.",
                            rows: 10

      sidebar do
        field :created_at, as: :date_time, disabled: true, format: "DDDD, T"
        field :updated_at, as: :date_time, disabled: true, format: "DDDD, T"
      end
    end
  end
end
