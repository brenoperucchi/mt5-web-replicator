# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

store = Store.create(name:'Store 1', active_at: DateTime.now)
store.traces.create(name: 'M15 Signals Premium', name_id:'-481414224', active_at: DateTime.now, telegram_option:'query_name_id', telegram_image:true)
store.traces.create(name: 'Swing Trading', name_id:'-481414224', active_at: DateTime.now, telegram_option:'query_name', telegram_image:false)
if Rails.env.development?
  store.traces.create(name: 'RoboSignal', name_id:'-481414224', active_at: nil, telegram_option:'query_name', telegram_image:true)
  store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: nil, telegram_option:'query_name_id', telegram_image:false)
end
