class CreateTelegramBotIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_bot_integrations do |t|
      t.string :name, null: false
      t.text :telegram_bot_token, null: false
      t.text :telegram_webhook_token, null: false
      t.string :telegram_chat_id, null: false
      t.jsonb :stripe_price_ids, default: [], null: false
      t.text :offer_message, null: false
      t.string :default_language, default: "en", null: false
      t.string :telegram_bot_username, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :telegram_bot_integrations, :telegram_webhook_token, unique: true
    add_index :telegram_bot_integrations, :active
  end
end
