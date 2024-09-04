require 'rails_helper'

RSpec.describe 'OrdersHistory API', type: :request do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @trace = create(:trace, :copy, stores: [@store], instrument_control: true)
    @trace2 = create(:trace, :copy2, stores:[@store])
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, user:@user_admin)
    @customer = create(:customer, :customer, user:@user_customer)
    @account_server = create(:account_server)
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2], instrument_control:true, account_server: @account_server)
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging', account_server: @account_server)
    @account_copy2 = create(:account, :copy2, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2], account_server: @account_server)
    
    post '/api/v2/copy/post/imentore_copy/2_21/broker_name/10100/HEDGING', 
      params: {"imentore_copy"=>"{\"orders_open\":{
                \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
                \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"-0.07\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
              }}"}
  end

  describe 'POST /api/v2/slave/orders_history/post/imentore_slave/2_21/broker_name/20100/HEDGING' do
    let(:file) { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'api', 'v2', 'orders_history.json')) }
    
    it 'Conciliate Orders - Verify profit and do action close slave' do
      slave1 = @account1.slaves.where(comment: "10000001").take
      slave2 = @account1.slaves.where(comment: "10000002").take
      expect(slave1.profit).to be == 0.0

      post '/api/v2/slave/post/signal_slave/1_53/broker_name/20100/HEDGING', 
        params: {"body"=> "{'account_login':'20100', 'magic_number':'9905', 'action':'OPEN', 'order_state':'OPEN', 'meta_state':'OPEN', 'ticket_slave_id':'20000001', 'ticket_master_id':'10000001', 'ticket_deal':'10000001', 'order_symbol':'AUDCAD', 'order_type':'1', 'price_open':'126725', 'price_close':'0', 'volume':'1.00', 'stop_loss':'127205', 'take_profit':'125780', 'profit':'1.00', 'comment':'10000001', 'open_at':'2024.07.26 10:30:44', 'closed_at':'', 'timezone':'-3', 'time_trader':'2024.07.26 10:30:12', 'time_gmt':'2024.07.26 13:30:12', 'meta_message':'#1838276377 - Ticket: 125959719 - OrderCreate - Symbol: WINQ24 - Type: 1  - Volume: 1.00 - TP: 125780 - SL: 127205 - Action: OPEN - Meta State: OPEN - LogMessage: #1838276377 - Ticket: 125959719 - Log Info - LastError: 4754 - Retcode: 10009 - ResultComment: Request executed - Attempt: 0'}"}
      post '/api/v2/slave/post/signal_slave/1_53/broker_name/20100/HEDGING', 
        params: {"body"=> "{'account_login':'20100', 'magic_number':'9905', 'action':'OPEN', 'order_state':'OPEN', 'meta_state':'OPEN', 'ticket_slave_id':'20000002', 'ticket_master_id':'10000002', 'ticket_deal':'10000002', 'order_symbol':'AUDCAD', 'order_type':'1', 'price_open':'126725', 'price_close':'0', 'volume':'1.00', 'stop_loss':'127205', 'take_profit':'125780', 'profit':'1.00', 'comment':'10000002', 'open_at':'2024.07.26 10:30:44', 'closed_at':'', 'timezone':'-3', 'time_trader':'2024.07.26 10:30:12', 'time_gmt':'2024.07.26 13:30:12', 'meta_message':'#1838276377 - Ticket: 125959719 - OrderCreate - Symbol: WINQ24 - Type: 1  - Volume: 1.00 - TP: 125780 - SL: 127205 - Action: OPEN - Meta State: OPEN - LogMessage: #1838276377 - Ticket: 125959719 - Log Info - LastError: 4754 - Retcode: 10009 - ResultComment: Request executed - Attempt: 0'}"}
      
      post '/api/v2/slave/orders_history/post/imentore_slave/2_21/broker_name/20100/HEDGING', 
        params: { logfile: file }

      slave2.reload
      slave1.reload
      expect(slave1.profit).to be == 1.00
      expect(slave2.profit).to be == 1.00
      expect(TransactionSlave.find_by(comment: "10000001").state).to be == "executed"
      expect(TransactionSlave.find_by(comment: "10000002").state).to be == "executed"

      post '/api/v2/slave/post/signal_slave/1_53/broker_name/20100/HEDGING', 
        params: {"body"=> "{'account_login':'20100', 'magic_number':'9905', 'action':'CLOSED', 'order_state':'CLOSED', 'meta_state':'CLOSED', 'ticket_slave_id':'20000001', 'ticket_master_id':'10000001', 'ticket_deal':'10000001', 'order_symbol':'AUDCAD', 'order_type':'1', 'price_open':'126725', 'price_close':'0', 'volume':'1.00', 'stop_loss':'127205', 'take_profit':'125780', 'profit':'1.50', 'comment':'10000001', 'open_at':'2024.07.26 10:30:44', 'closed_at':'', 'timezone':'-3', 'time_trader':'2024.07.26 10:30:12', 'time_gmt':'2024.07.26 13:30:12', 'meta_message':'#1838276377 - Ticket: 125959719 - OrderCreate - Symbol: WINQ24 - Type: 1  - Volume: 1.00 - TP: 125780 - SL: 127205 - Action: OPEN - Meta State: OPEN - LogMessage: #1838276377 - Ticket: 125959719 - Log Info - LastError: 4754 - Retcode: 10009 - ResultComment: Request executed - Attempt: 0'}"}
      post '/api/v2/slave/post/signal_slave/1_53/broker_name/20100/HEDGING', 
        params: {"body"=> "{'account_login':'20100', 'magic_number':'9905', 'action':'CLOSED', 'order_state':'CLOSED', 'meta_state':'CLOSED', 'ticket_slave_id':'20000001', 'ticket_master_id':'10000002', 'ticket_deal':'10000002', 'order_symbol':'AUDCAD', 'order_type':'1', 'price_open':'126725', 'price_close':'0', 'volume':'1.00', 'stop_loss':'127205', 'take_profit':'125780', 'profit':'1.50', 'comment':'10000002', 'open_at':'2024.07.26 10:30:44', 'closed_at':'', 'timezone':'-3', 'time_trader':'2024.07.26 10:30:12', 'time_gmt':'2024.07.26 13:30:12', 'meta_message':'#1838276377 - Ticket: 125959719 - OrderCreate - Symbol: WINQ24 - Type: 1  - Volume: 1.00 - TP: 125780 - SL: 127205 - Action: OPEN - Meta State: OPEN - LogMessage: #1838276377 - Ticket: 125959719 - Log Info - LastError: 4754 - Retcode: 10009 - ResultComment: Request executed - Attempt: 0'}"}
 
      expect(TransactionSlave.find_by(comment: "10000001").profit).to be == 1.50
      expect(TransactionSlave.find_by(comment: "10000001").profit).to be == 1.50
      expect(TransactionSlave.find_by(comment: "10000001").state).to be == "closed"
      expect(TransactionSlave.find_by(comment: "10000002").state).to be == "closed"

      expect(Order.find_by(content_id: 10000001).present?).to be true
      expect(Order.find_by(content_id: 10000001).slaves.count).to be 1
      expect(Order.find_by(content_id: 10000001).slaves.first.ticket_master).to be == 10000001
      expect(Order.find_by(content_id: 10000002).slaves.count).to be 1
      expect(Order.find_by(content_id: 10000002).slaves.first.ticket_master).to be == 10000002
    end

    it 'Conciliate Orders - Create New Slave in older Order' do
      order = create(:order, trace_id: @trace.id, store:@store, account_id: @account_copy2.id)

      post '/api/v2/slave/post/signal_slave/1_53/broker_name/20100/HEDGING', 
        params: {"body"=> "{'account_login':'20100', 'magic_number':'9905', 'action':'OPEN', 'order_state':'OPEN', 'meta_state':'OPEN', 'ticket_slave_id':'20000001', 'ticket_master_id':'10000001', 'ticket_deal':'10000001', 'order_symbol':'AUDCAD', 'order_type':'1', 'price_open':'126725', 'price_close':'0', 'volume':'1.00', 'stop_loss':'127205', 'take_profit':'125780', 'profit':'0', 'comment':'10000001', 'open_at':'2024.07.26 10:30:44', 'closed_at':'', 'timezone':'-3', 'time_trader':'2024.07.26 10:30:12', 'time_gmt':'2024.07.26 13:30:12', 'meta_message':'#1838276377 - Ticket: 125959719 - OrderCreate - Symbol: WINQ24 - Type: 1  - Volume: 1.00 - TP: 125780 - SL: 127205 - Action: OPEN - Meta State: OPEN - LogMessage: #1838276377 - Ticket: 125959719 - Log Info - LastError: 4754 - Retcode: 10009 - ResultComment: Request executed - Attempt: 0'}"}
        
      post '/api/v2/slave/orders_history/post/imentore_slave/2_21/broker_name/20100/HEDGING',
        params: { logfile: file }

      expect(Order.find_by(content_id: 10000015).present?).to be true
      expect(Order.find_by(content_id: 10000015).slaves.count).to be == 0
      # expect(Order.find_by(content_id: 10000015).slaves.first.comment).to be == "10000015"
      # expect(Order.find_by(content_id: 10000015).slaves.first.ticket_slave).to be == 90000002
      # expect(Order.find_by(content_id: 10000015).slaves.first.profit).to be == 1.00
    end

    it 'Conciliate Orders - Create New Slave in New Order' do
      post '/api/v2/slave/orders_history/post/imentore_slave/2_21/broker_name/20100/HEDGING',
        params: { logfile: file }

      @account1.reload
      slaves = TransactionSlave.where(ticket_master: 99000013)
      expect(slaves.count).to be == 0
      # expect(slaves.first.state).to be == "closed"

      expect(Order.find_by(content_id: 99000013).present?).to be false
      # expect(Order.find_by(content_id: 99000013).slaves.count).to be == 1
      # expect(Order.find_by(content_id: 99000013).slaves.first.comment).to be == "manual_order"
      # expect(Order.find_by(content_id: 99000013).slaves.first.ticket_slave).to be == 99000015
      # expect(Order.find_by(content_id: 99000013).slaves.first.profit).to be == 1.00
    end
  end

end    