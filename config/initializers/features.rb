# Feature flags. Read ENV here, once; the rest of the app checks
# Rails.configuration.x.*.
#
# ENABLE_TELEGRAM (default off): experimental Telegram signal ingestion and
# bot notifications. When off, no Telegram code runs, the telegram-bot-ruby
# gem is never required and no Telegram ENV/credentials are needed.
Rails.configuration.x.telegram_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch("ENABLE_TELEGRAM", "false")) || false
