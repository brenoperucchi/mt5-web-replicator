# Bootstraps a fresh database: a default plan, one store, an admin login and
# the Stripe payment row. Idempotent, so `bin/rails db:seed` can be re-run.
#
# Environment variables (see .env.example):
#   SEED_ADMIN_EMAIL / SEED_ADMIN_PASSWORD  admin login (password required in production)
#   SEED_STORE_NAME / SEED_STORE_URL        first store
#   TELEGRAM_API_ID / _HASH / _NUMBER       optional; only for the experimental Telegram feature
#   STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET

# Telegram is disabled by default (ENABLE_TELEGRAM); only store its settings
# when they're actually provided.
telegram_attributes = {
  telegram_api_id: ENV['TELEGRAM_API_ID'],
  telegram_api_hash: ENV['TELEGRAM_API_HASH'],
  telegram_api_number: ENV['TELEGRAM_API_NUMBER']
}.compact_blank

plan = Plan.find_or_create_by!(name: 'Default Plan') do |p|
  p.amount = 0
  p.amount_extra = 0
end

store_url = ENV.fetch('SEED_STORE_URL', 'store-1')
store = Store.find_by(url: store_url) || Store.create!({
  name: ENV.fetch('SEED_STORE_NAME', 'Store 1'), url: store_url, email: "#{store_url}@example.com",
  active_at: Time.current, volume_default: 0.10, state: :enable, plan: plan
}.merge(telegram_attributes))

# NOTE: traces and accounts aren't seeded. Trace requires an existing
# CustomerPlan (which itself requires a Payment record); create them from the
# admin once the store and its payment are in place.

admin_email = ENV.fetch('SEED_ADMIN_EMAIL', 'admin@example.com')
if User.exists?(email: admin_email)
  puts "Admin user #{admin_email} already exists"
else
  admin_password = Rails.env.production? ? ENV.fetch('SEED_ADMIN_PASSWORD') : ENV.fetch('SEED_ADMIN_PASSWORD', 'password123')
  admin_customer = Customer.new(name: 'Admin', role: 'administrator', role_control: 'owner')
  admin_customer.build_user(email: admin_email, password: admin_password, store: store)
  admin_customer.save!
  puts "Admin user created: #{admin_email} (login at /users/sign_in)"
end

# Default payment provider: Stripe. Keys may be left blank here:
# PaymentMethod::Stripe falls back to the STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET
# env vars when the Payment row has none.
# Register the webhook in Stripe at https://<APP_DOMAIN>/payments/webhook/<payment id>.
stripe_method = PaymentMethod.find_or_create_by!(handle: 'stripe') { |pm| pm.name = 'Stripe' }
stripe_payment = Payment.find_or_create_by!(payment_method: stripe_method, store: store) do |payment|
  payment.api_token     = ENV['STRIPE_SECRET_KEY'].presence
  payment.webhook_token = ENV['STRIPE_WEBHOOK_SECRET'].presence
end
puts "Stripe payment ##{stripe_payment.id} ready (webhook path: /payments/webhook/#{stripe_payment.id})"
