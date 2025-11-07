# Telegram Bot Setup Guide (Legacy Integration)

> **⚠️ This documentation is for the LEGACY Telegram bot integration.**  
> For the new **reusable bot integration system** that supports multiple bots via Avo admin, see [`docs/telegram-bot-integrations.md`](./telegram-bot-integrations.md).

This guide explains how to set up the **legacy** Telegram bot integration for payments and channel invitations.

## Prerequisites

1. A Telegram bot created via [@BotFather](https://t.me/botfather)
2. Your bot token
3. A private Telegram channel where the bot is added as an admin
4. Stripe account with API keys configured

## Setup Steps

### 1. Configure Rails Credentials

Add your Telegram bot credentials to Rails credentials:

```bash
rails credentials:edit --environment=development
```

Add the following structure:

```yaml
telegram:
  bot_token: YOUR_BOT_TOKEN
  bot_nickname: your_bot_name
  members_only_chat_id: -100XXXXXXXXX # Your private channel chat ID
  webhook_token: your_generated_secret_token # REQUIRED - for webhook security
```

**IMPORTANT**: `webhook_token` is **required** in all environments (development, staging, production). Generate one using `SecureRandom.hex(32)`.

**Finding your channel chat ID:**

- Add [@userinfobot](https://t.me/userinfobot) to your channel
- It will show the channel ID (negative number for groups/channels)

### 2. Make Bot Admin of Channel

1. Go to your private Telegram channel
2. Open channel settings → Administrators
3. Add your bot as an administrator
4. Grant it permission to "Invite users via link" or "Add new admins"

### 3. Set Bot Description

Set the bot's description that shows when users first open the bot (before clicking Start):

**For Ukrainian Audiobooks Bot:**

1. Start a conversation with [@BotFather](https://t.me/botfather)
2. Send `/setdescription` for full description
3. Send `/setabouttext` for short description (shown in search)
4. Select your bot
5. Paste the appropriate description (see examples below)

**Short Description** (120 chars max, shows in search):

```
Access to popular Ukrainian audiobooks. Instant access after payment.
```

**Full Description** (512 chars max, shows before Start):

```
📚 Get unlimited access to the most popular Ukrainian audiobooks in a private Telegram group. Latest releases and classics in one place. Support Ukrainian creators. Instant access after payment.
```

Alternatively, set it programmatically:

```ruby
# Set short description (shown in search)
short_desc = "Access to popular Ukrainian audiobooks. Instant access after payment."
TelegramBotService.new.set_bot_short_description(short_desc)

# Set full description (shown before Start)
description = "📚 Get unlimited access to the most popular Ukrainian audiobooks in a private Telegram group. Latest releases and classics in one place. Support Ukrainian creators. Instant access after payment."
TelegramBotService.new.set_bot_description(description)
```

**Note:** For translations in other languages, see `docs/telegram-bot-description.md`.

### 4. Register Bot Commands

To make commands appear in the bot's menu, you can either use BotFather or set them programmatically:

#### Option 1: Using BotFather (Manual)

1. Start a conversation with [@BotFather](https://t.me/botfather)
2. Send `/setcommands`
3. Select your bot
4. Paste the following commands list:

```
start - Start the bot and subscribe
status - Check your subscription status and manage account
cancel - Cancel current operation
```

#### Option 2: Programmatically (Recommended)

You can set commands directly from Rails console:

```ruby
# Delete all existing commands first
TelegramBotService.new.delete_commands

# Set commands for all supported languages (recommended)
# This ensures commands appear regardless of user's Telegram language
TelegramBotService.new.set_commands(set_for_all_languages: true)

# Or set commands for default language only
TelegramBotService.new.set_commands

# Or set custom commands for all languages
TelegramBotService.new.set_commands([
  { command: "start", description: "Start the bot and subscribe" },
  { command: "status", description: "Check subscription status and manage account" },
  { command: "cancel", description: "Cancel current operation" },
], set_for_all_languages: true)

# Verify commands were set
TelegramBotService.new.get_commands
```

**Note**: The commands are already implemented in `app/controllers/telegram/webhooks_controller.rb`.

**Important**: After setting commands, they may not appear immediately in Telegram clients due to caching. Users need to:

1. Type "/" in the chat to see available commands
2. Refresh/restart the Telegram app
3. Commands appear in the bot's menu (three dots → Bot Commands in some clients)

### 5. Set Up Telegram Webhook

The webhook URL should point to:

- **Development**: `http://your-domain.ngrok.io/telegram/webhooks` (use ngrok for local testing)
- **Production**: `https://your-domain.com/telegram/webhooks`

#### Generate Webhook Secret Token

**IMPORTANT**: The webhook token is **required in all environments** (development, staging, production) for security:

1. Generate a secure random token (e.g., in Rails console):

   ```ruby
   SecureRandom.alphanumeric(32)  # Generates a 32-character alphanumeric string
   ```

2. Add it to Rails credentials for each environment:

   ```bash
   # For development:
   rails credentials:edit --environment=development

   # For production:
   rails credentials:edit --environment=production
   ```

   Add under `telegram:` in each environment file:

   ```yaml
   telegram:
     webhook_token: your_generated_secret_token_here
   ```

   **Note**: You can use the same token for all environments, or generate different ones for each.

#### Set the Webhook

You can set the webhook using the Rails console:

```ruby
# example setting webhook without secret token:
# TelegramBotService.new.set_webhook(url: "https://8ef72953dd3b.ngrok-free.app/telegram/webhooks")

# Set webhook with secret token
token = Rails.application.credentials.dig(:telegram, :webhook_token)
TelegramBotService.new.set_webhook(
  url: "https://988f8df883a6.ngrok-free.app/telegram/webhooks",
  secret_token: token
)
```

Or manually via Telegram API:

```
# Without secret token:
https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook?url=https://your-domain.com/telegram/webhooks

# With secret token:
https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook?url=https://your-domain.com/telegram/webhooks&secret_token=YOUR_SECRET_TOKEN
```

**Note**: Once you set a `secret_token` when configuring the webhook, Telegram will send it in the `X-Telegram-Bot-Api-Secret-Token` header with every request. Your app verifies this matches your configured token.

### 6. Configure Stripe Webhook

In your Stripe Dashboard, create a webhook endpoint pointing to:

- **Development**: `http://your-domain.ngrok.io/stripe_payment_links/webhooks`
- **Production**: `https://your-domain.com/stripe_payment_links/webhooks`

> **Note**: The route `stripe_payment_links/webhooks` is for the legacy integration.  
> For the new reusable bot integrations, use `/stripe/bots/webhooks` instead.

**Required Events:**

- `checkout.session.completed`

Copy the webhook signing secret and add it to your Rails credentials:

```yaml
stripe:
  signing_secret: whsec_...
```

### 7. Run Database Migration

```bash
rails db:migrate
```

This adds the `telegram_user_id` column to the users table.

### 8. Test the Integration

1. Start a conversation with your bot on Telegram
2. Send `/start` command
3. The bot should respond with a Stripe payment link
4. Complete the payment
5. After successful payment, you should:
   - Be automatically added to the private channel
   - Receive a confirmation message

## How It Works

1. **User starts chat**: User sends `/start` to the bot
2. **Payment link generated**: Bot creates a Stripe Payment Link and sends it to the user
3. **User pays**: User completes payment via Stripe
4. **Webhook triggered**: Stripe sends `checkout.session.completed` event to your webhook
5. **Channel invitation**: Bot automatically invites the user to the private Telegram channel
6. **Confirmation**: Bot sends a success message to the user

## Troubleshooting

### Bot doesn't respond to /start

- Check that the webhook is properly set: `TelegramBotService.new.get_webhook_info`
- Verify the webhook URL is accessible
- Check Rails logs for errors

### Users not added to channel

- Verify bot is admin of the channel
- Check bot has "Invite users" permission
- Check channel chat ID is correct in credentials
- Review Rails logs for Telegram API errors

### Payment links not generating

- Verify Stripe API key is configured correctly
- Check that a price ID is configured in `config/settings.yml`
- Review Rails logs for Stripe API errors

## Security Notes

- Keep your bot token secure and never commit it to version control
- Use HTTPS for webhooks in production
- Consider setting a `webhook_token` for additional Telegram webhook security
- Stripe webhooks are automatically verified using the signing secret
