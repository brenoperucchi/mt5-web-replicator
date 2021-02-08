# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)


def symbol_list
"
AUDCAD: AUDCAD
AUDCHF: AUDCHF
AUDJPY: AUDJPY
AUDNZD: AUDNZD
AUDUSD: AUDUSD
BTCUSD: BTCUSD
CADCHF: CADCHF
CADJPY: CADJPY
CHFJPY: CHFJPY
CHFSGD: CHFSGD
EURAUD: EURAUD
EURCAD: EURCAD
EURCHF: EURCHF
EURGBP: EURGBP
EURJPY: EURJPY
EURNOK: EURNOK
EURPLN: EURPLN
EURNZD: EURNZD
EURSGD: EURSGD
EURUSD: EURUSD
EURZAR: EURZAR
GBPAUD: GBPAUD
GBPCAD: GBPCAD
GBPCHF: GBPCHF
GBPJPY: GBPJPY
GBPNOK: GBPNOK
GBPNZD: GBPNZD
GBPSGD: GBPSGD
GBPUSD: GBPUSD
NOKJPY: NOKJPY
NOKSEK: NOKSEK
NZDCAD: NZDCAD
NZDCHF: NZDCHF
NZDJPY: NZDJPY
NZDUSD: NZDUSD
USDCAD: USDCAD
USDCHF: USDCHF
USDJPY: USDJPY
USDNOK: USDNOK
USDPLN: USDPLN
USDSEK: USDSEK
USDZAR: USDZAR
GOLD: XAUUSD
US30: UsaInd
NAS100: UsaTec
BRAIND: WING21
"
end


if Rails.env.development?
  	store = Store.create(name:'Store 1', active_at: DateTime.now, master: '39426385 5100601')

  	store.traces.create(name: 'RoboSignal', name_id:'-481414224', active_at: DateTime.now, telegram_option:'query_name',
						telegram_image:true, meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.05, 0.05",
						symbol_list: symbol_list)
  	store.traces.create(name: 'Perucchi Inc', name_id:'-340961920', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1125, volume_list:"0.01, 0.02",
						symbol_list: symbol_list)
  	store.traces.create(name: 'PipsNation', name_id:'-1001340273590', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1120, volume_list:"0.05, 0.05",
						symbol_list: symbol_list)
  	store.traces.create(name: 'Swing Trading ViP', name_id:'-1001159029077', active_at: DateTime.now, telegram_option:'query_name',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1125, volume_list:"0.01, 0.02",
						symbol_list: symbol_list)  	
  	store.traces.create(name: 'Canal Easy Trader Robot Dolar', name_id:'-1001454553108', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1110, volume_list:"1",
						symbol_list: symbol_list)
  	store.traces.create(name: 'Canal Easy Trader Robot Indice', name_id:'-1001366232829', active_at: DateTime.now, telegram_option:'query_name_id',
						telegram_image:false, meta_host: '192.168.1.245', meta_port: 1110, volume_list:"1",
						symbol_list: symbol_list)
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


