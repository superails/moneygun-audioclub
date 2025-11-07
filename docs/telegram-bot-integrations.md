# Telegram Bot Integrations

A reusable template system for creating paid membership Telegram bots. This system allows admins to configure new Telegram-Stripe integrations via Avo admin panel without any code changes.

## Architecture

This system acts as a **middleware between Telegram and Stripe**:

- **No Rails database storage** for users, organizations, or subscriptions
- **Telegram user ID** stored in Stripe customer metadata
- **Bot identification** via webhook token matching
- **Separate from existing integration** - completely isolated

## Setup

### 1. Create a Bot Integration in Avo

1. Navigate to **Telegram Bot Integrations** in Avo admin
2. Click **New**
3. Fill in the following fields:

   - **Name**: Admin-friendly identifier (e.g., "Audiobook Premium Bot")
   - **Active**: Enable/disable this integration
   - **Telegram Bot Token**: Get from [BotFather](https://t.me/botfather)
   - **Telegram Webhook Token**: ⚠️ **Hidden from UI** - Auto-generated on create, automatically managed
   - **Telegram Chat ID**: Channel or group ID (can be negative for groups)
   - **Telegram Bot Username**: ⚠️ **Auto-fetched** - Hidden on create, read-only on edit. Automatically fetched from Telegram API after token is provided.
   - **Stripe Price IDs**: One per line or comma-separated (e.g., `price_123\nprice_456`)
   - **Default Language**: `en`, `uk`, or `ru`
   - **Offer Message**: Custom HTML-formatted offer description shown in `/start`

### 2. Automatic Registration

When you create or update a bot integration with `active: true`, the system automatically:

1. **Generates Webhook Token**: Creates a unique 32-character token (stored encrypted)
2. **Fetches Bot Username**: Retrieves bot username from Telegram API (displayed in show/edit views)
3. **Registers Bot Commands**: Sets `/start`, `/status`, and `/cancel` commands for all supported languages (en, uk, ru)
4. **Sets Webhook URL**: Configures the webhook endpoint with your auto-generated secret token

**No manual setup required!** The registration happens asynchronously in the background via `TelegramBotRegistrationJob`.

#### Webhook URL Configuration

The webhook URL is automatically built and always uses HTTPS:

- **Development**: `https://localhost:3000/telegram/bots/webhooks` (use ngrok for external access)
- **Production**: `https://your-domain.com/telegram/bots/webhooks`

You can override the base URL using:

- `RAILS_HOST` environment variable (e.g., `RAILS_HOST=your-domain.com` or `RAILS_HOST=your-ngrok-url.ngrok-free.app`)

The webhook token is **auto-generated**, encrypted in the database, and **completely hidden from the Avo UI** for security. It's automatically used when registering the webhook with Telegram.

#### Manual Registration (if needed)

If automatic registration fails or you need to re-register manually:

```ruby
bot = TelegramBotIntegration.find_by(name: "Your Bot Name")
TelegramBotRegistrationJob.perform_now(bot.id)
```

### 3. Configure Stripe Webhook

In Stripe Dashboard, create a webhook endpoint:

- **URL**: `https://your-domain.com/stripe/bots/webhooks`
- **Events to send**:
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `checkout.session.completed`
  - `invoice.paid` (fires when subscription invoice is paid - important!)
  - `invoice.payment_succeeded` (alternative event for invoice payment)

Copy the webhook signing secret and add to Rails credentials:

```bash
rails credentials:edit --environment=production
```

```yaml
stripe:
  private_key: sk_... # Stripe secret key (used for API calls)
  public_key: pk_... # Stripe publishable key (optional, for frontend)
  signing_secret:
    - whsec_... # Webhook signing secret (can be array for multiple endpoints)
```

## User Flow

1. **User sends `/start`**: Bot shows customizable offer message with "Get Started Now" and "Maybe Later" buttons
2. **User clicks "Get Started Now"**: Bot fetches prices from Stripe API and shows available plans with buttons
3. **User selects a plan**: Bot generates Stripe checkout session (subscription or payment mode based on price)
   - Shows "Generating payment link..." which is replaced in-place with payment terms and button
4. **User completes payment**: Stripe webhook triggers and grants Telegram channel access
   - Idempotent processing prevents duplicate operations
5. **User can use `/status`**: Shows subscription status (active/expiring/cancelled/none) with:
   - Channel access link (if subscribed)
   - Billing portal link (if subscription exists) for managing subscription

## Features

### ✅ No Database Dependencies

- Users, organizations, subscriptions are **not stored in Rails**
- All data lives in Stripe (customers, subscriptions)
- Telegram user ID stored in Stripe customer metadata

### ✅ Multiple Bot Support

- Single webhook endpoint identifies bot by webhook token
- Each bot can have different prices, channels, and offer messages
- Completely isolated from each other

### ✅ Flexible Pricing

- Supports both **subscription** (recurring) and **payment** (one-time) modes
- Automatically detects mode from Stripe price type
- Shows only active prices (archived prices are automatically filtered out)
- Price IDs support newline or comma-separated input (automatically normalized)

### ✅ Internationalization

- Configurable default language per bot
- Auto-detects user's Telegram language
- Supports English (`en`), Ukrainian (`uk`), Russian (`ru`)
- Generic messages in locale files (`config/locales/bot.*.yml`)

### ✅ Robust Error Handling

- Graceful handling of channel invite failures (provides invite link)
- Subscription status checks (active/expiring/cancelled/none)
- Stripe API error handling
- **Idempotent webhook processing** - Duplicate Stripe events are safely ignored (24-hour cache)

## API Reference

### Controllers

**`Telegram::BotsController`**

- `POST /telegram/bots/webhooks` - Single endpoint for all Telegram bot webhooks
- Identifies bot by `X-Telegram-Bot-Api-Secret-Token` header
- Handles `/start`, `/status`, `/cancel` commands
- Processes callback queries for plan selection

**`Stripe::BotsController`**

- `POST /stripe/bots/webhooks` - Stripe webhook handler
- Grants Telegram channel access on subscription activation
- Handles both subscription and one-time payments

### Services

**`TelegramBotIntegrationService`**

- Bot-specific Telegram API wrapper
- Methods: `send_message`, `invite_user_to_channel`, `get_channel_invite_link`, etc.

**`StripeBotService`**

- Direct Stripe API integration (no Pay gem)
- Methods: `fetch_prices`, `create_checkout_session`, `get_subscription_status`

### Models

**`TelegramBotIntegration`**

- Stores bot configuration
- Validates required fields
- Normalizes `stripe_price_ids` (handles arrays, strings, comma/newline-separated)
- Locale detection from Telegram messages

## Customization

### Offer Message

Edit the `offer_message` field in Avo to customize the `/start` command message. Supports HTML formatting.

### Generic Messages

All other bot messages are in locale files:

- `config/locales/bot.en.yml`
- `config/locales/bot.uk.yml`
- `config/locales/bot.ru.yml`

Update these files to change generic messages (plan selection, payment, status, etc.).

## Troubleshooting

### Bot Not Responding

1. Check webhook is set correctly: `GET https://api.telegram.org/bot<TOKEN>/getWebhookInfo`
2. Verify webhook token matches in Avo admin
3. Check Rails logs for errors

### Users Not Getting Channel Access

1. Verify Stripe webhook is configured correctly
2. Check webhook secret in Rails credentials
3. Verify `telegram_user_id` and `telegram_chat_id` are in subscription/customer metadata
4. Check bot has admin permissions in the channel/group
5. Check Rails logs for webhook processing errors
6. Verify idempotency isn't blocking valid events (check cache for processed event IDs)

### Price Not Showing

1. Verify price ID exists in Stripe
2. Check price is `active: true` (archived prices are automatically filtered out)
3. Verify price ID is in bot's `stripe_price_ids` field (supports newline or comma-separated)
4. Check format: price IDs must start with `price_`
5. Review Rails logs for Stripe API errors when fetching prices

## Security

- ✅ Webhook token verification (required in all environments)
- ✅ Stripe webhook signature verification
- ✅ Bot identified by secret token (no public IDs)
- ✅ Sensitive tokens encrypted in database (deterministic encryption for webhook_token to enable searching)
- ✅ Webhook token completely hidden from Avo UI (auto-generated and auto-managed)
- ✅ Bot token masked on index/show views, only visible on edit/new (prevents saving masked values)
- ✅ No email verification (as per requirements)
- ✅ Telegram user ID stored in Stripe metadata (not email)
- ✅ Idempotent webhook processing prevents duplicate operations
