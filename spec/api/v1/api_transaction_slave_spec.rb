require 'rails_helper'

RSpec.describe API::V1::APITransactionsSlave do
  before(:context) do
    # @store = create(:store, master: '5077669')
    # @trace = create(:trace, :first, store: @store)
    # post '/api/v1/orders', params: {
    #   "message_id"=>"723517440",
    #   "message"=>"BUY 80.39\n\nTP 80.19\nTP 79.89\nTP 79.39\nSL 81.39",
    #   "photo_path"=>"#{Rails.root}/tmp/500028400464_282900.jpg",
    #   "name"=>"RoboSignal",
    #   "name_id"=>"-481414224"
    # }
  end

  # This should return the minimal set of attributes required to create a valid
  # Finances::Entry. As you add validations to Finances::Entry, be sure to
  # adjust the attributes here as well.

  # This should return the minimal set of values that should be in the session
  # in order to pass any filters (e.g. authentication) defined in
  # Finances::EntriesController. Be sure to keep this updated too.
  # let!(:store) { FactoryBot.create(:store)   }
  # let!(:trace) { FactoryBot.create(:trace, :first, store: store)}
  # let(:job_image_worker) { ImageWorker.new.perform.first }
  # let(:order) { FactoryBot.create(:order, :m15_trace) }
  # let(:transaction) { FactoryBot.create(:transaction) }

  describe API::V1::Traces do
    context 'POST' do
      it 'Save transaction from metatrader order' do
        
        post '/api/v1/transactions/request/entire/signal_slave/1_50/5634743/NETTING', params:{

    

    # it 'verify kind order' do
    #   @order = @trace.orders.find_by(message_id: 723517440)
    #   expect(@order.kind).not_to be == nil
    # end

    # context 'POST /api/v1/orders' do
      
    #   it 'verify kind order' do
    #     @order = @trace.orders.find_by(message_id: 723517440)
    #     expect(@order.kind).to be == "order"
    #   end

    #   it 'save a telegram trace message' do
    #     expect(Order.first.state).to be == "prepared"
    #     expect(Order.first.symbol).to be == "CADJPY"
    #     # expect(response).to be_success
    #     expect(response.status).to eq(201)
    #     expect(JSON.parse(response.body)).to be == {"id"=>1, "message"=>"BUY 80.39\n\nTP 80.19\nTP 79.89\nTP 79.39\nSL 81.39", "message_id"=>"723517440", "symbol"=>"CADJPY", "trace"=>"RoboSignal"}
    #   end

    #   it 'verify lot information' do
    #     @trace.update(take_profit: 'normal')
    #     get '/api/v2/orders/723517440'
    #     expect(JSON.parse(response.body)['lots']).to eq([0.05])

    #     @trace.update(take_profit: 'Agressive')
    #     get '/api/v2/orders/723517440'
    #     expect(JSON.parse(response.body)['lots']).to eq([0.03, 0.02])

    #     @trace.update(take_profit: 'Superagressive')
    #     get '/api/v2/orders/723517440'
    #     expect(JSON.parse(response.body)['lots']).to eq([0.03, 0.02, 0.02])
    #   end
    # end


    # context 'GET /api/v1/orders/723517440' do
    #   it 'get information of message id' do
    #     get '/api/v1/orders/723517440'
    #     expect(JSON.parse(response.body)['id']).to eq(1)
    #     expect(JSON.parse(response.body)['message_id']).to eq('723517440')
    #     expect(JSON.parse(response.body)['message'].tr("\n", " ")).to be == 'BUY 80.39  TP 80.19 TP 79.89 TP 79.39 SL 81.39'
    #     expect(JSON.parse(response.body)['symbol']).to eq('CADJPY')
    #   end
    # end

    # context 'GET /api/v1/orders/' do
    #   it 'return all sign to execute' do
    #     get '/api/v1/stores'
    #     # expect(response).to be_success
    #     expect(response.status).to eq(200)
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['message_id']).to eq('723517440')
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['type']).to eq('BUY')
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['symbol']).to eq('CADJPY')
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['price_request']).to eq('80.39')
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['SL']).to eq('81.39')
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['TP']).to eq(['80.19', '79.89'])
    #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['lots']).to eq([0.03, 0.02])
    #   end
    # end
    # context 'POST /api/v1/orders/transaction' do
    #   it 'Save transaction from metatrader order' do
        
    #     post '/api/v1/orders/transaction', params:{
    #       "chat_id"=>"1",
    #       "message_id"=>"723517440",
    #       "provider"=>"1",
    #       "provider_name"=>"RoboSignal",
    #       "symbol"=>"CADJPY",
    #       "action"=>"EXECUTION",
    #       "kind"=>"0",
    #       "price_request"=>"80.39",
    #       "price_open"=>"80.38",
    #       "stop_loss"=>"81.39",
    #       "take_profit"=>"80.19",
    #       "lot"=> "0.03",
    #       "comment"=>"RoboSignal",
    #       "magic"=>"123456",
    #       "ticket"=>"363873673",
    #       "open_at"=>"2020.10.21 01:18:09",
    #       "response"=>"10009"
    #     }

    #     expect(JSON.parse(response.body)['state']).to eq('executed')
    #     expect(JSON.parse(response.body)['ticket']).to eq('363873673')
    #     expect(JSON.parse(response.body)['action']).to eq('EXECUTION')
    #     expect(JSON.parse(response.body)['kind']).to eq('0')
    #     expect(JSON.parse(response.body)['symbol']).to eq('CADJPY')
    #     expect(JSON.parse(response.body)['price_request']).to eq('80.39')
    #     expect(JSON.parse(response.body)['price_open']).to eq('80.38')
    #     expect(JSON.parse(response.body)['stop_loss']).to eq('81.39')
    #     expect(JSON.parse(response.body)['take_profit']).to eq('80.19')
    #     expect(JSON.parse(response.body)['lot']).to eq('0.03')
    #     expect(JSON.parse(response.body)['comment']).to eq('RoboSignal')
    #     expect(JSON.parse(response.body)['magic']).to eq('123456')
    #     expect(JSON.parse(response.body)['ticket']).to eq('363873673')
    #     expect(JSON.parse(response.body)['open_at']).to eq('2020-10-21T01:18:09.000Z')
    #   end

    #   it 'verify kind order' do
    #     @order = @trace.orders.find_by(message_id: 723517440)
    #     @order.execute
    #     expect(@order.kind).to be == "order"
    #     expect(@order.state).to be == 'executed'
    #   end
      
    # end
    # context 'POST /api/v1/orders' do
    #   it 'Error transaction from metatrader order' do
    #     post '/api/v1/orders/transaction', params:{
    #       'chat_id': 1, 'message_id': '723517440', 'provider': 1, 'provider_name': 'RoboSignal', 'symbol': 'CADJPY', 'action': 'EXECUTION', 'kind': 1, 'price_request': '80.39', 'price_open': 79.509, 'stop_loss': 'None', 'take_profit': 'None', 'comment': 'RoboSignal #1', 'magic': 123456, 'ticket': 363928013, 'open_at': '2020.10.22 06:36:53', 'response': 'ERROR_SETTING_SL_TP', 'response_value': 'None', 'environment': 'local'
    #     }
    #     expect(JSON.parse(response.body)['state']).to eq('error')
    #   end
    # end
    # context '/api/v1/traces' do 
    #   it 'post close transaction' do
    #     transaction = create(:transaction, :first, order: @store.traces.first.orders.first)
    #     transaction.execute
    #     post '/api/v1/traces/master', params:{
    #       'message': '5077669|CLOSED|EURNZD|363873673|1|1.182750|1.183030|0.020000|1.198500|1.178500|-0.610000'
    #     }
    #     expect(response.body).to eq('true')
    #     expect(@store.traces.first.orders.first.transactions.first.profit.to_f).to be == -0.61
    #     expect(@store.traces.first.orders.first.transactions.first.response).to be == "5077669|CLOSED|EURNZD|363873673|1|1.182750|1.183030|0.020000|1.198500|1.178500|-0.610000"
    #     expect(@store.traces.first.orders.first.transactions.first.state).to be == 'closed'       
    #     expect(@store.traces.first.orders.first.state).to be == 'closed'       
    #   end
    # end

  end
end