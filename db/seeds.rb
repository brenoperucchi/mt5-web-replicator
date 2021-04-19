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
						telegram_image:true, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'PipsNation', name_id:'-1001340273590', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1120, take_profit_limit: 2)
  	store.traces.create(name: 'PipsMaster', name_id:'-1001136746513', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1125, take_profit_limit: 2)
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: nil, telegram_option:'query_name',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1125, take_profit_limit: 2)  	
  	store.traces.create(name: 'Canal Easy Trader Robot Dolar', name_id:'-1001454553108', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'Canal Easy Trader Robot Indice', name_id:'-1001366232829', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'Tradexxfx', name_id:'-1001299578719', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1120, take_profit_limit: 2)

  	Store.first.traces.each do |trace|
  		Instrument::SYMBOLLIST.each do |symbol|
  			trace.instruments.create(symbol: symbol[:symbol], name: symbol[:name], volumes:symbol[:volumes])
  		end
  	end
elsif Rails.env.production?
  	store = Store.create(name:'Store 1', active_at: DateTime.now, master: '3007712').

  	store.traces.create(name: 'M15 Signals Premium', name_id:'-1001222448337', active_at: nil, telegram_option:'query_name_id',
						telegram_image:true, meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05",
						symbol_list: symbol_list)
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: nil, telegram_option:'query_name',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05",
						symbol_list: symbol_list)
  	store.traces.create(name: 'PipsNation', name_id:'-1001340273590', active_at: nil, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.10, 0.05",
						symbol_list: symbol_list)
end


