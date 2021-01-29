# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

if Rails.env.development?
  	store = Store.create(name:'Store 1', active_at: DateTime.now, master: '39426385 5100601')

  	store.traces.create(name: 'RoboSignal', name_id:'-481414224', active_at: DateTime.now, telegram_option:'query_name',
						telegram_image:true, lots: 0.05, take_profit:'Agressive',
						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.05, 0.10"
					 )
  	store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, lots: 0.05, take_profit:'Agressive',
						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.01, 0.02"
					 )
  	store.traces.create(name: 'PipsNation', name_id:'-1001330590845', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, lots: 0.05, take_profit:'Agressive',
						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05"
					 )
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: nil, telegram_option:'query_name',
						telegram_image:false, lots: 0.03, take_profit:'Normal',
						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.01, 0.02"
					 )
elsif Rails.env.production?
  	store = Store.create(name:'Store 1', active_at: DateTime.now, master: '3007712').

  	store.traces.create(name: 'M15 Signals Premium', name_id:'-1001222448337', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:true, lots: 0.04, take_profit:'Agressive',
						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05"
					 )
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: DateTime.now, telegram_option:'query_name',
						telegram_image:false, lots: 0.03, take_profit:'Normal',
						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05"
					 )
  	store.traces.create(name: 'PipsNation', name_id:'-1001330590845', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, lots: 0.05, take_profit:'Agressive',
  						meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05"
  					 )
end