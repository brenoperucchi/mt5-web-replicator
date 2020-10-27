# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

if not Rails.env.test?
  store = Store.create(name:'Store 1', active_at: DateTime.now)
end
if Rails.env.development?
  store.traces.create(name: 'RoboSignal', name_id:'-481414224', active_at: DateTime.now, telegram_option:'query_name', telegram_image:true, lots: 0.05, take_profit:'Agressive')
  store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: DateTime.now, telegram_option:'query_name_id', telegram_image:false, lots: 0.05, take_profit:'Agressive')
elsif Rails.env.production?
  store.traces.create(name: 'M15 Signals Premium', name_id:'-1001222448337', active_at: DateTime.now, telegram_option:'query_name_id', telegram_image:true, lots: 0.04, take_profit:'Agressive')
  store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: DateTime.now, telegram_option:'query_name', telegram_image:false, lots: 0.03, take_profit:'Normal')
end