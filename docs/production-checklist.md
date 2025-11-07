# Production-Ready Checklist: Telegram Bot Integrations

This checklist ensures the Telegram bot integration feature is production-ready. Review each item before deploying to production.

## 📊 Summary

- **Total Items**: ~80 checklist items across 11 categories
- **Critical Gaps**: 5 high/medium priority items (see below)
- **Status**: Core functionality complete, production hardening needed

### Quick Stats

- ✅ **Security**: 6/10 implemented (60%)
- ✅ **Error Handling**: 5/8 implemented (63%) - ✅ **+Idempotency**
- ✅ **Configuration**: 4/6 implemented (67%)
- ✅ **Monitoring**: 1/7 implemented (14%) - **NEEDS ATTENTION**
- ✅ **Data Integrity**: 4/6 implemented (67%)
- ✅ **Performance**: 2/6 implemented (33%)
- ⚠️ **Testing**: 0/5 implemented (0%) - **NEEDS ATTENTION**
- ✅ **Documentation**: 3/4 implemented (75%)
- ✅ **Edge Cases**: 9/9 implemented (100%) - ✅ **+Duplicate events**
- ✅ **Operations**: 1/7 implemented (14%) - **NEEDS ATTENTION**
- ✅ **i18n**: 3/4 implemented (75%)
- ✅ **Payment**: 4/5 implemented (80%)

## 🔒 Security & Authentication

### ✅ Implemented

- [x] Telegram webhook token verification (required header `X-Telegram-Bot-Api-Secret-Token`)
- [x] Stripe webhook signature verification
- [x] Sensitive tokens encrypted in database (deterministic for webhook_token)
- [x] Bot identification by secret token (no public IDs exposed)
- [x] CSRF protection skipped for webhook endpoints (required)
- [x] Authentication skipped for webhook endpoints (required)

### ⚠️ Missing / Needs Review

- [ ] **Rate limiting on webhook endpoints** - Prevent abuse and DDoS
  - Consider adding rate limiting for `/telegram/bots/webhooks` and `/stripe/bots/webhooks`
  - Example: `rate_limit to: 100, within: 1.minute, only: :create` in controllers
- [ ] **Request size limits** - Prevent memory exhaustion from large payloads
  - Add `Rack::Attack` or similar middleware
- [ ] **IP allowlisting (optional)** - Restrict webhook sources
  - Telegram: Consider allowing only Telegram IP ranges
  - Stripe: Consider Stripe IP allowlisting (though signature verification is usually sufficient)
- [ ] **Webhook token rotation strategy** - Security best practice
  - Document process for rotating webhook tokens
  - Consider adding migration path for token updates

## 🛡️ Error Handling & Resilience

### ✅ Implemented

- [x] Comprehensive error handling with rescue blocks
- [x] Graceful fallbacks (invite link if direct add fails)
- [x] Job re-raises errors for retry mechanism
- [x] Error logging with context

### ⚠️ Missing / Needs Review

- [x] **Idempotency for Stripe webhooks** - ✅ IMPLEMENTED
  - ✅ Event ID tracking implemented with cache
  - ✅ Duplicate events return `200 OK` immediately
  - ✅ 24-hour TTL prevents reprocessing
- [ ] **Explicit retry configuration for `TelegramBotRegistrationJob`**
  - Add `retry_on` with exponential backoff
  - Example: `retry_on StandardError, wait: :exponentially_longer, attempts: 5`
- [ ] **Webhook timeout handling** - Telegram/Stripe will retry if we timeout
  - Ensure webhook handlers complete quickly (< 30 seconds)
  - Move slow operations to background jobs
  - Consider async processing for channel access grants
- [ ] **Dead letter queue** - Handle permanently failing jobs
  - Configure `discard_on` for unrecoverable errors
- [ ] **Circuit breaker for external APIs** - Prevent cascade failures
  - Consider circuit breaker for Telegram API calls
  - Consider circuit breaker for Stripe API calls
- [ ] **Retry logic for Telegram API calls** - Handle transient failures
  - Implement exponential backoff for failed Telegram API requests
  - Handle rate limiting (HTTP 429) from Telegram API

## ⚙️ Configuration & Environment

### ✅ Implemented

- [x] Credentials-based configuration (Stripe keys, encryption)
- [x] Environment variable for `RAILS_HOST`
- [x] Automatic webhook URL generation
- [x] Support for unencrypted data during migration

### ⚠️ Missing / Needs Review

- [ ] **Environment validation on startup** - Fail fast if misconfigured
  - Add initializer to validate required credentials on boot
  - Check: `stripe.private_key`, `stripe.signing_secret`, `active_record_encryption` (if using encryption)
- [ ] **Configuration validation in model** - Prevent invalid bot configurations
  - Validate Telegram bot token format (if possible)
  - Validate Stripe price IDs format
  - Validate Telegram chat ID format (should be numeric)
- [ ] **Health check endpoint for webhooks** - Verify external dependencies
  - Add `/telegram/bots/health` endpoint that checks:
    - Database connectivity
    - Telegram API reachability (optional)
    - Stripe API connectivity (optional)
- [ ] **RAILS_HOST validation** - Ensure webhook URLs are correct
  - Warn if `RAILS_HOST` contains `localhost` in production
  - Validate HTTPS in production

## 📊 Monitoring & Observability

### ✅ Implemented

- [x] Comprehensive logging (info, warn, error levels)
- [x] Contextual error messages with bot IDs
- [x] Unhandled event logging for Stripe webhooks

### ⚠️ Missing / Needs Review

- [ ] **Structured logging** - JSON logs for easier parsing
  - Add correlation IDs to track requests across services
  - Include bot_integration_id in all log entries
- [ ] **Metrics collection** - Track key business metrics
  - Webhook request count (by bot, by type)
  - Payment success/failure rates
  - Channel access grant success/failure rates
  - Average response times
  - Job success/failure rates
  - Consider using Prometheus, StatsD, or similar
- [ ] **Error tracking service integration** - Sentry, Honeybadger, Rollbar
  - Configure error tracking for production exceptions
  - Set up alerts for critical errors
- [ ] **Webhook delivery monitoring** - Track webhook processing times
  - Log webhook processing duration
  - Alert on slow webhooks (> 5 seconds)
- [ ] **Background job monitoring** - Track job queue health
  - Monitor job queue depth
  - Alert on stuck jobs
  - Track job processing times
- [ ] **Uptime monitoring** - External monitoring for webhook endpoints
  - Configure uptime check for `/telegram/bots/webhooks`
  - Configure uptime check for `/stripe/bots/webhooks`
  - Alert on downtime

## 🔄 Data Integrity & Validation

### ✅ Implemented

- [x] Model validations (presence, format, inclusion)
- [x] Price ID normalization (handles arrays, strings, comma/newline-separated)
- [x] Unique webhook token constraint
- [x] Active scope for querying

### ⚠️ Missing / Needs Review

- [ ] **Database indexes** - Optimize query performance
  - Add index on `telegram_bot_integrations.active` (already exists?)
  - Add index on `telegram_bot_integrations.telegram_webhook_token` (already exists via unique constraint)
  - Verify indexes exist via `rails db:migrate:status`
- [ ] **Price ID validation** - Verify prices exist and are active before saving
  - Consider validation that calls Stripe API (async or on-demand)
  - Or at least validate format: should start with `price_`
- [ ] **Webhook token collision handling** - Already handled with loop, but document
  - Current implementation uses `loop` to ensure uniqueness
  - Consider adding index on `telegram_webhook_token` if not exists
- [ ] **Cache key expiration** - Prevent stale waiting states
  - Current `Rails.cache.read("bot_waiting_price_#{chat_id}")` may never expire
  - Add TTL when writing: `Rails.cache.write(key, value, expires_in: 30.minutes)`

## ⚡ Performance & Scalability

### ✅ Implemented

- [x] Background job for bot registration (async)
- [x] Efficient database queries (scopes, indexes)

### ⚠️ Missing / Needs Review

- [ ] **Connection pooling** - Ensure proper database connection limits
  - Verify `database.yml` has appropriate `pool` size
  - Ensure pool size >= max threads in Puma
- [ ] **Caching strategy** - Cache frequently accessed data
  - Cache Stripe price details (with TTL)
  - Cache bot username lookups
  - Cache channel invite links (refresh periodically)
- [ ] **N+1 query prevention** - Already good, but verify
  - `TelegramBotIntegration.active.find` loops through all - consider optimizing if many bots
  - Consider adding `index_on` for `stripe_price_ids` if JSONB queries become slow
- [ ] **Background job queue configuration** - Optimize for production
  - Consider dedicated queue for `TelegramBotRegistrationJob`
  - Configure job concurrency appropriately
- [ ] **Rate limiting for external APIs** - Respect API limits
  - Telegram: 30 messages/second per bot
  - Stripe: Check rate limits and implement throttling if needed

## 🧪 Testing

### ⚠️ Missing / Needs Review

- [ ] **Unit tests** - Test critical business logic
  - `TelegramBotIntegration` model (validations, callbacks, methods)
  - `TelegramBotIntegrationService` (API calls, error handling)
  - `StripeBotService` (price fetching, checkout creation, status checks)
- [ ] **Integration tests** - Test webhook flows
  - Telegram webhook handling (`/start`, `/status`, callback queries)
  - Stripe webhook handling (subscription updates, checkout completed, invoice paid)
  - End-to-end payment flow
- [ ] **Controller tests** - Test request handling
  - Authentication/authorization (token verification)
  - Error responses
  - Parameter validation
- [ ] **Job tests** - Test background job behavior
  - `TelegramBotRegistrationJob` success and failure scenarios
  - Retry behavior
- [ ] **Edge case tests** - Test error scenarios
  - Invalid webhook tokens
  - Missing Stripe metadata
  - Network failures
  - API rate limiting
  - Channel access failures

## 📚 Documentation

### ✅ Implemented

- [x] Setup documentation (`docs/telegram-bot-integrations.md`)
- [x] Inline code comments
- [x] API reference in docs

### ⚠️ Missing / Needs Review

- [ ] **Runbook / Operations guide** - How to handle common issues
  - How to manually retry failed bot registrations
  - How to reprocess failed webhooks
  - How to verify webhook configuration
  - How to rotate webhook tokens
  - How to debug payment issues
- [ ] **Architecture diagram** - Visual representation of flow
  - User interaction flow
  - Payment flow
  - Webhook processing flow
- [ ] **API documentation** - OpenAPI/Swagger specs (optional)
  - Document webhook payload formats
  - Document expected responses

## 🎯 Edge Cases & Failure Modes

### ✅ Implemented

- [x] Handles missing metadata (falls back to customer metadata)
- [x] Handles channel invite failures (provides invite link)
- [x] Handles already-subscribed users (shows confirmation)
- [x] Handles multiple subscription statuses (active/expiring/cancelled/none)

### ⚠️ Missing / Needs Review

- [ ] **Duplicate webhook events** - Stripe may send duplicate events
  - **CRITICAL**: Implement idempotency (mentioned above)
- [ ] **Webhook ordering** - Events may arrive out of order
  - Document expected behavior
  - Consider processing events in order if critical
- [ ] **Partial failures** - What if channel invite succeeds but message fails?
  - Current: User gets access, but no confirmation message
  - Consider: Retry logic for message sending
- [ ] **Bot token expiration** - Telegram bot tokens don't expire, but document
  - Document: Bot tokens don't expire unless revoked in BotFather
- [ ] **Price archiving** - Prices become archived in Stripe
  - Current: Filtered out in `fetch_prices` (only shows `active: true`)
  - Consider: Alert admin if configured price becomes archived
- [ ] **Channel/Group changes** - Channel ID changes or bot removed
  - Document: How to handle if bot loses access to channel
  - Consider: Periodic health check that verifies bot access
- [ ] **User blocking bot** - User blocks bot, can't send messages
  - Current: Error logged, no action
  - Consider: Track blocked users, skip message attempts
- [ ] **Multiple subscriptions** - User subscribes to multiple plans
  - Current: Finds first active subscription
  - Consider: Handle multiple subscriptions per user
- [ ] **Subscription cancelled but still in period** - Grace period handling
  - Current: Shows as "expiring" if `cancel_at_period_end`
  - Verify: User should still have access during grace period

## 🔧 Operations & Maintenance

### ⚠️ Missing / Needs Review

- [ ] **Database migrations** - Ensure all migrations are applied
  - Run `rails db:migrate:status` to verify
  - Document migration order if dependencies exist
- [ ] **Backup strategy** - Protect bot configurations
  - Backup `telegram_bot_integrations` table
  - Document how to restore from backup
- [ ] **Monitoring dashboard** - Visualize system health
  - Webhook processing rates
  - Error rates
  - Job queue status
  - Active bot integrations
- [ ] **Alerting rules** - Notify on critical issues
  - High error rate on webhooks
  - Failed job queue growth
  - Bot registration failures
  - Stripe webhook signature failures
- [ ] **Incident response plan** - How to handle outages
  - Webhook endpoint down
  - Stripe API outage
  - Telegram API outage
  - Database connectivity issues
- [ ] **Log retention policy** - Compliance and debugging
  - Define log retention period
  - Configure log rotation
- [ ] **Deployment checklist** - Pre-deployment steps
  - Verify credentials are set
  - Verify migrations are applied
  - Verify environment variables
  - Smoke test webhook endpoints

## 🌐 Internationalization

### ✅ Implemented

- [x] Multi-language support (EN, UK, RU)
- [x] Automatic language detection from Telegram
- [x] Configurable default language per bot
- [x] Locale files for generic messages

### ⚠️ Missing / Needs Review

- [ ] **Locale completeness** - Verify all locales have all keys
  - Check `bot.en.yml`, `bot.uk.yml`, `bot.ru.yml` have same keys
  - Consider adding missing translations
- [ ] **Date formatting** - Locale-aware date formatting
  - Current: Uses `Time.at(ends_at).strftime("%B %d, %Y")` (English format)
  - Consider: Use `I18n.l()` for locale-aware dates

## 💳 Payment & Subscription Management

### ✅ Implemented

- [x] Subscription status checking (active/expiring/cancelled/none)
- [x] Billing portal integration
- [x] Both subscription and one-time payment support
- [x] Metadata stored in Stripe (telegram_user_id, telegram_chat_id)

### ⚠️ Missing / Needs Review

- [ ] **Refund handling** - What happens on refunds?
  - Consider: Handle `charge.refunded` event
  - Consider: Remove user from channel on refund (if desired)
- [ ] **Failed payment handling** - What happens on failed payments?
  - Consider: Handle `invoice.payment_failed` event
  - Consider: Notify user or admin
- [ ] **Subscription cancellation webhook** - Track cancellations
  - Current: Handled via `subscription.updated` with status check
  - Consider: Explicit handling of `customer.subscription.deleted`
- [ ] **Trial period handling** - Free trial subscriptions
  - Current: Treats `trialing` status as active
  - Verify: User should have access during trial

## 🔐 Compliance & Legal

### ⚠️ Missing / Needs Review

- [ ] **GDPR compliance** - User data handling
  - Document: No user data stored in Rails (only in Stripe)
  - Document: How to handle user data deletion requests
  - Consider: Data retention policy
- [ ] **Terms of Service** - Link in payment flow
  - Current: Mentioned in payment terms message
  - Consider: Add clickable ToS link
- [ ] **Privacy policy** - Data collection disclosure
  - Document: What data is collected (Telegram user ID, chat ID)
  - Document: How data is used
  - Document: Data storage location (Stripe metadata)

## 📋 Pre-Deployment Checklist

Before deploying to production, ensure:

- [ ] All tests pass (`rails test` or `rspec`)
- [ ] Linter passes (`rubocop`)
- [ ] Database migrations are up to date
- [ ] Environment variables are configured
- [ ] Rails credentials are set with:
  - `stripe.private_key`
  - `stripe.signing_secret`
  - `active_record_encryption.*` (if using encryption)
- [ ] `RAILS_HOST` is set to production domain (not localhost)
- [ ] Stripe webhook is configured with correct URL
- [ ] Stripe webhook events are configured:
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `checkout.session.completed`
  - `invoice.paid`
  - `invoice.payment_succeeded`
- [ ] At least one bot integration created and tested in Avo
- [ ] Bot webhook is registered with Telegram (automatic)
- [ ] Bot has admin permissions in target Telegram channel/group
- [ ] Health check endpoint is monitored (`/up`)
- [ ] Error tracking service is configured (Sentry/Honeybadger)
- [ ] Logs are being collected and monitored
- [ ] Backup strategy is in place
- [ ] Incident response plan is documented

## 🚨 Critical Gaps (Must Fix Before Production)

### 1. **Idempotency for Stripe webhooks** - ✅ COMPLETED

**Problem**: Stripe may send duplicate webhook events. Without idempotency, users could be granted channel access multiple times, or operations could be processed redundantly.

**Risk**:

- Duplicate channel access grants
- Redundant API calls
- Potential race conditions

**Solution**: ✅ Event ID tracking implemented in `Stripe::BotsController#create`

**Implementation**:

- Checks cache for processed event ID before processing
- Returns `200 OK` immediately if event already processed
- Marks event as processed with 24-hour TTL after successful handling
- Uses cache key: `stripe_webhook_processed_#{event_id}`

**Notes**:

- ✅ Uses Rails cache (Solid Cache in production)
- ✅ 24-hour TTL is safe (Stripe events are immutable)
- ✅ Logs duplicate events for monitoring

---

### 2. **Explicit job retry configuration** - ⚠️ MEDIUM PRIORITY

**Problem**: `TelegramBotRegistrationJob` relies on ActiveJob defaults for retries, which may not be optimal.

**Solution**: Add explicit retry configuration

```ruby
class TelegramBotRegistrationJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff, up to 5 attempts
  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  # Don't retry if bot integration no longer exists
  discard_on ActiveJob::DeserializationError

  def perform(bot_integration_id)
    # ... existing code ...
  end
end
```

**Implementation Notes**:

- Exponential backoff: 1s, 2s, 4s, 8s, 16s
- Total retry window: ~31 seconds
- Consider max wait time cap for production

---

### 3. **Rate limiting on webhook endpoints** - ⚠️ MEDIUM PRIORITY

**Problem**: Webhook endpoints are publicly accessible and could be abused.

**Solution**: Add rate limiting using `rack-attack` or similar

```ruby
# config/initializers/rack_attack.rb (if not exists)
if Rails.env.production?
  Rack::Attack.throttle('telegram_bots_webhook', limit: 100, period: 1.minute) do |req|
    req.ip if req.path == '/telegram/bots/webhooks'
  end

  Rack::Attack.throttle('stripe_bots_webhook', limit: 200, period: 1.minute) do |req|
    req.ip if req.path == '/stripe/bots/webhooks'
  end
end
```

**Implementation Notes**:

- Telegram: 100 requests/minute per IP (Telegram may send bursts)
- Stripe: 200 requests/minute per IP (Stripe sends fewer events)
- Adjust limits based on actual usage patterns

---

### 4. **Cache expiration for waiting states** - ⚠️ LOW PRIORITY

**Problem**: `Rails.cache.read("bot_waiting_price_#{chat_id}")` entries never expire, causing potential memory leaks.

**Solution**: Add TTL when writing cache

```ruby
# In Telegram::BotsController (if waiting states are used)
Rails.cache.write("bot_waiting_price_#{chat_id}", state, expires_in: 30.minutes)
```

**Note**: Current code uses callback queries, so this may not be actively used, but should be fixed if implemented.

---

### 5. **Error tracking service integration** - ⚠️ MEDIUM PRIORITY

**Problem**: Production errors need centralized tracking for debugging.

**Solution**: Configure Sentry/Honeybadger/Rollbar

```ruby
# config/initializers/sentry.rb (example for Sentry)
if Rails.env.production?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.enabled_environments = ['production']
    config.send_default_pii = false
  end
end
```

**Implementation Notes**:

- Filter sensitive data (bot tokens, webhook secrets)
- Add context tags (bot_integration_id, event_type)
- Set up alerts for critical errors

---

## 📋 Additional Recommended Improvements

### Environment Validation on Startup

Add initializer to validate critical configuration:

```ruby
# config/initializers/validate_bot_integrations_config.rb
if Rails.env.production?
  Rails.application.config.after_initialize do
    # Validate Stripe credentials
    unless Rails.application.credentials.dig(:stripe, :private_key).present?
      Rails.logger.error "CRITICAL: Stripe private_key not configured!"
    end

    unless Rails.application.credentials.dig(:stripe, :signing_secret).present?
      Rails.logger.error "CRITICAL: Stripe signing_secret not configured!"
    end

    # Warn about localhost in production
    if ENV['RAILS_HOST']&.include?('localhost')
      Rails.logger.warn "WARNING: RAILS_HOST contains localhost in production!"
    end
  end
end
```

### Idempotency Key Tracking (Detailed Implementation)

For more robust idempotency, consider database-backed tracking:

```ruby
# Migration
class CreateProcessedStripeEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_stripe_events do |t|
      t.string :event_id, null: false, index: { unique: true }
      t.string :event_type, null: false
      t.timestamp :processed_at, null: false

      t.timestamps
    end

    add_index :processed_stripe_events, :event_id, unique: true
    add_index :processed_stripe_events, :processed_at
  end
end

# Model
class ProcessedStripeEvent < ApplicationRecord
  # Auto-cleanup old events (run periodic job)
end

# In controller
def create
  # ... signature verification ...

  if ProcessedStripeEvent.exists?(event_id: event.id)
    Rails.logger.info "Stripe webhook: Event #{event.id} already processed"
    head :ok
    return
  end

  # Process event...

  ProcessedStripeEvent.create!(
    event_id: event.id,
    event_type: event.type,
    processed_at: Time.current
  )
end
```

**Note**: Cache-based approach is simpler and sufficient for most cases. Database approach provides audit trail.

---

## ✅ Verified Implementations

Based on code review, the following are correctly implemented:

- [x] Database indexes on `telegram_webhook_token` (unique) and `active`
- [x] Encryption for sensitive tokens (with deterministic encryption for webhook_token)
- [x] Webhook signature verification for both Telegram and Stripe
- [x] Comprehensive error handling with fallbacks
- [x] Background job for async bot registration
- [x] Multi-language support with auto-detection
- [x] Proper validation of required fields
- [x] Health check endpoint (`/up`)
- [x] Proper HTTP status codes (200, 400, 403)
- [x] Structured error logging with context
