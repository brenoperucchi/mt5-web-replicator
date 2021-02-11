# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)


def symbol_list
[
	{symbol:'AUDCAD', name: 'AUDCAD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'AUDCHF', name: 'AUDCHF', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'AUDJPY', name: 'AUDJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'AUDNZD', name: 'AUDNZD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'AUDUSD', name: 'AUDUSD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'BTCUSD', name: 'BTCUSD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'CADCHF', name: 'CADCHF', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'CADJPY', name: 'CADJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'CHFJPY', name: 'CHFJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'CHFSGD', name: 'CHFSGD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURAUD', name: 'EURAUD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURCAD', name: 'EURCAD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURCHF', name: 'EURCHF', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURGBP', name: 'EURGBP', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURJPY', name: 'EURJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURNOK', name: 'EURNOK', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURPLN', name: 'EURPLN', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURNZD', name: 'EURNZD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURSGD', name: 'EURSGD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURUSD', name: 'EURUSD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'EURZAR', name: 'EURZAR', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPAUD', name: 'GBPAUD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPCAD', name: 'GBPCAD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPCHF', name: 'GBPCHF', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPJPY', name: 'GBPJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPNOK', name: 'GBPNOK', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPNZD', name: 'GBPNZD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPSGD', name: 'GBPSGD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GBPUSD', name: 'GBPUSD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'NOKJPY', name: 'NOKJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'NOKSEK', name: 'NOKSEK', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'NZDCAD', name: 'NZDCAD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'NZDCHF', name: 'NZDCHF', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'NZDJPY', name: 'NZDJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'NZDUSD', name: 'NZDUSD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDCAD', name: 'USDCAD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDCHF', name: 'USDCHF', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDJPY', name: 'USDJPY', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDNOK', name: 'USDNOK', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDPLN', name: 'USDPLN', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDSEK', name: 'USDSEK', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'USDZAR', name: 'USDZAR', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'GOLD', name: 'XAUUSD', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'US30', name: 'UsaInd', volumes:"0.10, 0.10, 0.10, 0.10"},
	{symbol:'NAS100', name: 'UsaTec', volumes:"0.04, 0.03, 0.02, 0.01"},
	{symbol:'BRAIND', name: 'WING21', volumes:"0.20, 0.10, 0.10, 0.10"},
]
end


if Rails.env.development?
  	store = Store.create(name:'Store 1', active_at: DateTime.now, master: '39426385 5100601')

  	store.traces.create(name: 'RoboSignal', name_id:'-481414224', active_at: DateTime.now, telegram_option:'query_name',
						telegram_image:true, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'PipsNation', name_id:'-1001340273590', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1120, take_profit_limit: 2)
  	store.traces.create(name: 'PipsMaster', name_id:'-1001136746513', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1125, take_profit_limit: 2)
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: DateTime.now, telegram_option:'query_name',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1125, take_profit_limit: 2)  	
  	store.traces.create(name: 'Canal Easy Trader Robot Dolar', name_id:'-1001454553108', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)
  	store.traces.create(name: 'Canal Easy Trader Robot Indice', name_id:'-1001366232829', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 900, take_profit_limit: 2)

  	Store.first.traces.each do |trace|
  		symbol_list.each do |symbol|
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


