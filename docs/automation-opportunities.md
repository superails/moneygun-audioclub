## 🔧 Can Be Automated

### 1. **Stripe Price ID Validation** - ⚠️ HIGH VALUE

**Current State**: Admins manually enter price IDs. No validation that they exist or are active.

**Proposed Automation**:

- Validate price ID format (must start with `price_`)
- Async validation: Check if prices exist in Stripe API on save
- Show warnings/errors in Avo UI if prices are invalid or archived
- Prevent saving if critical prices are missing

**Implementation**:

```ruby
# In app/models/telegram_bot_integration.rb
validate :validate_stripe_price_ids

def validate_stripe_price_ids
  return if stripe_price_ids.blank?

  # Format validation
  invalid_format = stripe_price_ids.reject { |id| id.start_with?("price_") }
  if invalid_format.any?
    errors.add(:stripe_price_ids, "Invalid format: #{invalid_format.join(', ')}. Must start with 'price_'")
  end

  # Async validation can be done in background job or on-demand
end
```

**Benefits**:

- Prevents configuration errors
- Faster debugging of payment issues
- Better UX - catch errors early

---

### 2. **Telegram Chat ID Validation & Bot Permissions Check** - ⚠️ HIGH VALUE

**Current State**: Admins manually enter chat ID. No verification that bot has access or admin permissions.

**Proposed Automation**:

- Validate chat ID format (numeric, can be negative for groups)
- Verify bot can access the chat via `getChat` API
- Check if bot has admin permissions via `getChatMember` API
- Show validation results in Avo UI (warning/info messages)
- Disable bot if permissions are lost

**Implementation**:

```ruby
# In app/models/telegram_bot_integration.rb
validate :validate_telegram_chat_access, on: :update, if: -> { telegram_chat_id_changed? || telegram_bot_token_changed? }

def validate_telegram_chat_access
  return if telegram_bot_token.blank? || telegram_chat_id.blank?

  service = TelegramBotIntegrationService.new(self)

  # Check if bot can access chat
  chat_info = service.get_chat_info # New method needed
  unless chat_info && chat_info["ok"]
    errors.add(:telegram_chat_id, "Bot cannot access this chat. Verify bot is added to channel/group.")
    return
  end

  # Check if bot is admin (only if already saved with an ID)
  if id.present?
    is_admin = service.check_bot_admin_permissions # New method needed
    unless is_admin
      errors.add(:telegram_chat_id, "Bot is not an administrator in this chat. Add bot as admin to grant user access.")
    end
  end
rescue StandardError => e
  Rails.logger.error "Error validating chat access: #{e.message}"
  errors.add(:telegram_chat_id, "Unable to verify chat access. Check bot token and chat ID.")
end
```

**New Service Method Needed**:

```ruby
# In app/services/telegram_bot_integration_service.rb
def get_chat_info
  _make_request("getChat", { chat_id: @chat_id }, http_method: :post)
end

def check_bot_admin_permissions
  bot_info = get_bot_info
  return false unless bot_info

  bot_user_id = bot_info.dig("id")
  return false unless bot_user_id

  member_info = _make_request("getChatMember", {
    chat_id: @chat_id,
    user_id: bot_user_id
  }, http_method: :post)

  return false unless member_info && member_info["ok"]

  status = member_info.dig("result", "status")
  %w[creator administrator].include?(status)
end
```

**Benefits**:

- Prevents configuration errors that would cause payment failures
- Immediate feedback to admins
- Better error messages

---

## ❌ Cannot Be Automated (Requires Human Action)

1. **Creating Bot in BotFather** - Requires Telegram interaction
2. **Getting Bot Token from BotFather** - Requires human to copy token
3. **Adding Bot to Channel as Admin** - Requires Telegram UI or bot already needs permissions
4. **Configuring Stripe Webhook Endpoint** - Requires Stripe Dashboard access (can be API but needs admin)
5. **Copying Stripe Webhook Signing Secret** - Requires manual copy to Rails credentials
