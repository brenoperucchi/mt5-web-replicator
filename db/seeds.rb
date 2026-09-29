# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

telegram_attributes = {
  telegram_api_id: ENV.fetch('TELEGRAM_API_ID', '000000'),
  telegram_api_hash: ENV.fetch('TELEGRAM_API_HASH', 'test_telegram_api_hash'),
  telegram_api_number: ENV.fetch('TELEGRAM_API_NUMBER', '5500000000000')
}
if Rails.env.development?

  	plan = Plan.create!(name: 'Default Plan', amount: 0, amount_extra: 0)

  	store = Store.create!({name:'Store 1', active_at: Time.current, volume_default: 0.10, state: :enable,
					plan: plan, email: 'store1@example.com', url: 'store-1'}.merge(telegram_attributes))

  # NOTE: the original trace/account seeding here was removed. Trace requires an existing
  # CustomerPlan (which itself requires a Payment record), so it can't be bootstrapped from
  # an empty database without also seeding the billing domain. See PR discussion for details.

  admin_email    = ENV.fetch('SEED_ADMIN_EMAIL', 'admin@example.com')
  admin_password = ENV.fetch('SEED_ADMIN_PASSWORD', 'password123')
  admin_customer = Customer.new(name: 'Admin', role: 'administrator', role_control: 'owner')
  admin_customer.build_user(email: admin_email, password: admin_password, store: store)
  admin_customer.save!
  puts "Admin user created: #{admin_email} / #{admin_password} (login at /users/sign_in)"

elsif Rails.env.production?
  	store = Store.create({name:'Store 1', active_at: Time.current, volume_default: 0.10, state: :enable}.merge(telegram_attributes))

  	store.traces.create(name: 'SignalCopy', name_id:'2000', active_at: Time.current, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'copy')
  	store.traces.create({name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))  	
  	# store.traces.create({name: 'PipsNation', name_id:'-1001340273590', active_at: nil, telegram_option:'query_name_id',
			# 			telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))
  	# store.traces.create({name: 'PipsMaster', name_id:'-1001136746513', active_at: nil, telegram_option:'query_name_id',
			# 			telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))
  	# store.traces.create({name: 'Canal Easy Trader Robot Dolar', name_id:'-1001454553108', active_at: nil, telegram_option:'query_name_id',
			# 			telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))
  	# store.traces.create({name: 'Canal Easy Trader Robot Indice', name_id:'-1001366232829', active_at: nil, telegram_option:'query_name_id',
			# 			telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))
  	store.traces.create({name: 'Tradexxfx', name_id:'-1001299578719', active_at: Time.current, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))
  	store.traces.create({name: 'CleverPips', name_id:'-1001319789685', active_at: Time.current, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram'}.merge(telegram_attributes))
  	store.traces.create({name: 'ScalpingVip', name_id:'-1001532685975', active_at: Time.current, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 1, kind: 'telegram'}.merge(telegram_attributes))
end


# Default payment provider: Stripe. Idempotent, so db:seed can be re-run safely.
# Keys may be left blank here: PaymentMethod::Stripe falls back to the
# STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET env vars when the Payment row has none.
# Register the webhook in Stripe at https://<domain>/payments/webhook/<payment id>.
stripe_method = PaymentMethod.find_or_create_by!(handle: 'stripe') { |pm| pm.name = 'Stripe' }
stripe_payment = Payment.find_or_create_by!(payment_method: stripe_method, store: Store.first) do |payment|
  payment.api_token     = ENV['STRIPE_SECRET_KEY'].presence
  payment.webhook_token = ENV['STRIPE_WEBHOOK_SECRET'].presence
end
puts "Stripe payment ##{stripe_payment.id} ready (webhook path: /payments/webhook/#{stripe_payment.id})"




# Store.first.traces.each do |trace|
# 	next if trace.copy?
# 	Instrument::SYMBOLLIST.each do |symbol|
# 		trace.instruments.create(symbol: symbol[:symbol], name: symbol[:name], volumes:symbol[:volumes])
# 	end
# end
