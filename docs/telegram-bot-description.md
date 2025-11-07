# Telegram Bot Description Setup

This document provides recommended bot descriptions for **reusable Telegram bot integrations** created via the Avo admin panel.

> **Note**: This is for the new reusable bot integration system. For the old integration, see `docs/telegram-bot-setup.md`.

## Recommended Bot Descriptions (by language)

Use these descriptions when setting up your bot via BotFather or programmatically.

### English

**Short Description** (max 120 chars, shows in search):

```
Audiobooks in Ukrainian — international & Ukrainian titles. Instant access. Cancel anytime.
```

**Full Description** (max 512 chars, shows before Start):

```
🎧 Stop searching. Start listening. Get instant access to hundreds of curated audiobooks in Ukrainian — international bestsellers, Ukrainian classics, and timeless stories from around the world — in an exclusive private Telegram channel. Updated regularly. Listen anywhere. Immerse yourself in Ukrainian language and culture. Instant access after secure payment. Cancel anytime.
```

### Ukrainian / Українська

**Short Description**:

```
service = TelegramBotService.new
short_description = "Доступ до популярних українських аудіокниг. Миттєвий доступ після оплати."
service.set_bot_short_description(short_description)
```

**Full Description**:

```
service = TelegramBotService.new
description = "📚 Отримайте необмежений доступ до найпопулярніших українських аудіокниг у приватній групі Telegram. Найновіші релізи та класика в одному місці. Миттєвий доступ після оплати."
service.set_bot_description(description)
```

### Russian / Русский

**Short Description**:

```
Доступ к популярным украинским аудиокнигам. Мгновенный доступ после оплаты.
```

**Full Description**:

```
📚 Получите неограниченный доступ к самым популярным украинским аудиокнигам в приватной группе Telegram. Новейшие релизы и классика в одном месте. Мгновенный доступ после оплаты.
```

## Setting Programmatically

For **reusable bot integrations**, use `TelegramBotIntegrationService` with a specific bot:

```ruby
# Get your bot integration
bot = TelegramBotIntegration.find_by(name: "Your Bot Name")
service = TelegramBotIntegrationService.new(bot)

# Set short description (shown in search)
# Note: This method needs to be added to TelegramBotIntegrationService if not already present
service.set_bot_short_description("Audiobooks in Ukrainian — international & Ukrainian titles. Instant access. Cancel anytime.")

# Set full description (shown before Start)
service.set_bot_description("🎧 Stop searching. Start listening. Get instant access to hundreds of curated audiobooks in Ukrainian — international bestsellers, Ukrainian classics, and timeless stories from around the world — in an exclusive private Telegram channel. Updated regularly. Listen anywhere. Immerse yourself in Ukrainian language and culture. Instant access after secure payment. Cancel anytime.")
```

> **Note**: Bot descriptions are **not automatically set** when creating a bot integration. You must set them manually via BotFather or programmatically after creating the bot.

## Setting via BotFather

1. Start a conversation with [@BotFather](https://t.me/botfather)
2. Send `/setdescription` for full description
3. Send `/setabouttext` for short description
4. Select your bot
5. Paste the appropriate description
