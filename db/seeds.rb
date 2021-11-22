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
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'SignalCopy', name_id:'2000', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'robometa', accounts_accept:'6500361 5612933 39207589 39426385', magics_accept:'2000 0')
  	store.traces.create(name: 'PipsNation', name_id:'-1001340273590', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'PipsMaster', name_id:'-1001136746513', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')  	
  	store.traces.create(name: 'Canal Easy Trader Robot Dolar', name_id:'-1001454553108', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Canal Easy Trader Robot Indice', name_id:'-1001366232829', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Tradexxfx', name_id:'-1001299578719', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'CleverPips', name_id:'-1001319789685', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')

elsif Rails.env.production?
  	store = Store.create(name:'Store 1', active_at: DateTime.now, master: '3007712')

  	store.traces.create(name: 'SignalCopy', name_id:'2000', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'robometa', accounts_accept:'6500361 5612933 39207589 39426385', magics_accept:'2000 0')
  	store.traces.create(name: 'PipsNation', name_id:'-1001340273590', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'PipsMaster', name_id:'-1001136746513', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')  	
  	store.traces.create(name: 'Canal Easy Trader Robot Dolar', name_id:'-1001454553108', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Canal Easy Trader Robot Indice', name_id:'-1001366232829', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'Tradexxfx', name_id:'-1001299578719', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
  	store.traces.create(name: 'CleverPips', name_id:'-1001319789685', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, take_profit_limit: 2, kind: 'telegram', telegram_api_id: '980209', telegram_api_hash:'03062326232cb23c6770e7a735c2dae2', telegram_api_number:'5548984222627')
end


Store.first.traces.each do |trace|
	next if trace.kind != 'telegram'
	Instrument::SYMBOLLIST.each do |symbol|
		trace.instruments.create(symbol: symbol[:symbol], name: symbol[:name], volumes:symbol[:volumes])
	end
end