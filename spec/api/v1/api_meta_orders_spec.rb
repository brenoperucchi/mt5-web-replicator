require 'rails_helper'

RSpec.describe API::V1::APITransactionsCopy do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @trace = create(:trace, :copy, store: @store, instrument_control: true)
    @trace2 = create(:trace, :copy2, store: @store)
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, store:@store, user:@user_admin)
    @customer = create(:customer, :customer, store:@store, user:@user_customer)
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2], instrument_control:true)
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account4 = create(:account, :slave4, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account_copy2 = create(:account, :copy2, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2])
    
    post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
    params: {"orders"=>"
      {\"ticket_id\":483852116,\"open_price\":0.87114000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":1,\"magicnumber\":57392193,\"symbol\":\"EURGBP\",\"comment\":\"57392193\",\"open_at\":1668124835,\"timezone\":-4,\"state_meta\":null}//
      {\"ticket_id\":483854383,\"open_price\":1.16938000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395585,\"symbol\":\"GBPUSD\",\"comment\":\"57395585\",\"open_at\":1668130203,\"timezone\":-4,\"state_meta\":null}//
      {\"ticket_id\":483854633,\"open_price\":1.16734000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395828,\"symbol\":\"GBPUSD\",\"comment\":\"57395828\",\"open_at\":1668130644,\"timezone\":-4,\"state_meta\":null}//
      {\"ticket_id\":483857785,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", 
        "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
  end

  describe API::V1::APITransactionsCopy do

    context 'Trace - masters_scope'do 
      it 'With out restrict_magic on trace' do
        # @account_copy.trace_ids = 1
        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(@account_copy.name).to be == "5647753"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10001,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}// 
          {\"ticket_id\":10002,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}// 
          {\"ticket_id\":10003,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}// 
          {\"ticket_id\":10004,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", 
            "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        orders = Order.all
        expect(orders.count).to be == 16
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 0
        expect(orders.executed.count).to be == 8
        expect(orders.closed.count).to be == 8
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"", 
          "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        orders = Order.all
        expect(orders.count).to be == 16
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 0
        expect(orders.executed.count).to be == 0
        expect(orders.closed.count).to be == 16
        expect(orders.sum(&:profit_copy)).to be == 0
        expect(Transaction.closed_info.count).to be == 16
        expect(Trace.first.masters_scope(:masters, :closed).to_a.sum(&:profit)).to be == 0
        request.headers['Content-Type'] = 'application/json'
        request.headers['Accept'] = 'application/json'
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10001','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10002','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10003','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10004','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        orders = Order.all
        expect(orders.count).to be == 16
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 0
        expect(orders.executed.count).to be == 0
        expect(orders.closed.count).to be == 16
        expect(orders.sum(&:profit_copy).to_f).to be == 800.00
        expect(Trace.first.masters_scope(:masters, :closed).to_a.sum(&:profit).to_f).to be == 400.00
        expect(Transaction.closed_info.count).to be == 8
      end

      it 'With out restrict_magic on trace' do#, focus:true do
        # @account_copy.trace_ids = 1
        trace = Trace.first
        trace.magics_accept =  "10001"        
        trace.save

        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(@account_copy.name).to be == "5647753"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10001,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":10001,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}// 
          {\"ticket_id\":10002,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":10001,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}// 
          {\"ticket_id\":10003,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":10002,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}// 
          {\"ticket_id\":10004,\"open_price\":1.16541000,\"volume\":0.54000000,\"profit\":0,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":10002,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", 
            "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        orders = Order.all
        expect(orders.count).to be == 16
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 2
        expect(orders.executed.count).to be == 6
        expect(orders.closed.count).to be == 8
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"", 
          "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        orders = Order.all
        expect(orders.count).to be == 16
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 2
        expect(orders.executed.count).to be == 0
        expect(orders.closed.count).to be == 14
        expect(orders.sum(&:profit_copy)).to be == 0
        expect(Transaction.closed_info.count).to be == 14
        expect(Trace.first.masters_scope(:masters, :closed).to_a.sum(&:profit)).to be == 0
        request.headers['Content-Type'] = 'application/json'
        request.headers['Accept'] = 'application/json'
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10001','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10002','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10003','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/closed/5647753/HEDGING', params: {body:{'ticket_id':'10004','account_login':'5837683', 'magic_number':'200009', 'action':'CLOSED', 'order_state':'executed', 'meta_state':'CLOSED', 'ticket_slave_id':'368529373', 'order_symbol':'UsaRus', 'order_type':'1', 'price_open':'0', 'price_close':'1786.12', 'volume':'0.5', 'stop_loss':'1786.09', 'take_profit':'1704.47', 'profit':'100', 'comment':'368529065', 'open_at':'1680616804', 'timezone':'-3', 'meta_message':'Action: CLOSED | Symbol: UsaRus | TransactionID: 216001 | Ticket Master: 368529065 | Ticket Slave: 368529373 | Type: 1 | LastError: 4754 | Result Code: 10009 | Result Comment: Manual Closed'}.to_json}
        orders = Order.all
        expect(orders.count).to be == 16
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 2
        expect(orders.executed.count).to be == 0
        expect(orders.closed.count).to be == 14
        trace.save
        expect(orders.sum(&:profit_copy).to_f).to be == 800.00
        expect(trace.masters_scope(:masters, :closed).to_a.sum(&:profit).to_f).to be == 200.00
        expect(Transaction.closed_info.count).to be == 8
      end
    end

    context 'Traces - Close Orders' do
      it 'Traces with two accounts copys' do
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/201002/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":2011,\"open_price\":0.87114000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":1,\"magicnumber\":57392193,\"symbol\":\"EURGBP\",\"comment\":\"57392193\",\"open_at\":1668124835,\"timezone\":-4,\"state_meta\":null}//
          {\"ticket_id\":2012,\"open_price\":1.16938000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395585,\"symbol\":\"GBPUSD\",\"comment\":\"57395585\",\"open_at\":1668130203,\"timezone\":-4,\"state_meta\":null}",
           "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"201002", "account_mode"=>"HEDGING"}
        expect(Account.find_by_name(5647753).traces.first.masters.count).to be == 6
        expect(Account.find_by_name(5647753).traces.last.masters.count).to be == 6

        expect(Account.find_by_name(5647753).traces.first.transactions.count).to be == 6
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'executed').count).to be == 6
        expect(Account.find_by_name(5647753).traces.last.transactions.where(state:'executed').count).to be == 6
        
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'executed').count).to be == 6
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'executed').count).to be == 6
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'closed_info').count).to be == 0

        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/201002/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":2011,\"open_price\":0.87114000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":1,\"magicnumber\":57392193,\"symbol\":\"EURGBP\",\"comment\":\"57392193\",\"open_at\":1668124835,\"timezone\":-4,\"state_meta\":null}",
           "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"201002", "account_mode"=>"HEDGING"}
        expect(Account.find_by_name(5647753).traces.first.transactions.count).to be == 6
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'closed_info').count).to be == 1
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'executed').count).to be == 5
        expect(Account.find_by_name(5647753).traces.last.transactions.where(state:'executed').count).to be == 5
        
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'executed').count).to be == 5
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'closed_info').count).to be == 1
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'executed').count).to be == 5
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'closed_info').count).to be == 1

        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/201002/HEDGING', 
        params: {"orders"=>"",
           "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"201002", "account_mode"=>"HEDGING"}
        expect(Account.find_by_name(5647753).traces.first.transactions.count).to be == 6
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'closed_info').count).to be == 2
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'executed').count).to be == 4
        expect(Account.find_by_name(5647753).traces.last.transactions.where(state:'executed').count).to be == 4
        
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'executed').count).to be == 4
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'closed_info').count).to be == 2
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'executed').count).to be == 4
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'closed_info').count).to be == 2

        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"", 
            "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        expect(Account.find_by_name(5647753).traces.first.transactions.count).to be == 6
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'closed_info').count).to be == 6
        expect(Account.find_by_name(5647753).traces.first.transactions.where(state:'executed').count).to be == 0
        expect(Account.find_by_name(5647753).traces.last.transactions.where(state:'executed').count).to be == 0
        
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'executed').count).to be == 0
        expect(Account.find_by_name(201002).traces.first.transactions.where(state:'closed_info').count).to be == 6
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'executed').count).to be == 0
        expect(Account.find_by_name(201002).traces.last.transactions.where(state:'closed_info').count).to be == 6
      end
    end
    context 'Control Instrument' do# focus:true do
      it 'Hedging - Change instruments on copy to slaves' do
        account = Account.find_by_name(5634788)
        expect(account.id).to be == 3
        expect(account.balances.count).to be == 4
        expect(account.orders.count).to be == 4
        expect(account.balances.where(account_id: 3).count).to be == 4
        account.orders.each do |order|
          expect(order.slaves.where(account_id: 1).count).to be == 0
          expect(order.slaves.where(account_id: 2).count).to be == 1
          expect(order.slaves.where(account_id: 3).count).to be == 1
          expect(order.slaves.where(account_id: 4).count).to be == 0
        end
        # %w(483852116 483854383 483854633 483857785).each do |account_name|
          # account
          # expect(Order.find)
        # end
      end
    end
    context 'Control Instrument'do 
      it 'Hedging - Change instruments on copy to slaves' do
        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(@account_copy.name).to be == "5647753"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10001,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        order = Order.find_by(content_id: 10001)          
        expect(order.trace.instrument_control).to be == true
        expect(order.content_id).to be == "10001"
        expect(order.state).to be == "executed"
        expect(order.symbol).not_to be == "GBPCAD"
        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(order.transactions.first.symbol).to be == "GBPUSD"
        expect(order.slaves.first.symbol).to be == "GBPCAD"
        expect(order.slaves.first.symbol).not_to be == "GBPUSD"
        
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10002,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        order = Order.find_by(content_id: 10002)          
        expect(order.content_id).to be == "10002"
        expect(order.state).to be == "executed"
        expect(order.symbol).to be == "GBPUSD"
        expect(order.transactions.first.symbol).to be == "GBPUSD"
        expect(order.slaves.first.symbol).to be == "GBPCAD"
        expect(order.slaves.first.symbol).not_to be == "GBPUSD"
      end
      it 'Trace - Create order all traces'do 
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10003,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        orders = Order.where(content_id: 10003)
        expect(orders.count).to be == 2
        order = orders.last
        expect(order.trace.instrument_control).to be == nil
        expect(order.account.name).to be == "5647753"
        expect(order.account.instrument_control).to be == true
        expect(order.trace.name).to be == "SignalCopy2"
        expect(order.transactions.first.symbol).to be == "GBPUSD"
        expect(order.slaves.first.symbol).to be == "GBPUSD"
      end
      
      it 'Trace - One trace disable'do 
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10004,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        slaves = TransactionSlave.where(ticket_master: 10004)
        expect(slaves.count).to be == 3
        expect(slaves[0].trace).to be == @trace
        expect(slaves[1].trace).to be == @trace
        expect(slaves[2].trace).to be == @trace2
        
        @trace2.soft_destroy
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"
          {\"ticket_id\":10005,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
        slaves = TransactionSlave.where(ticket_master: 10005)
        expect(slaves.count).to be == 2
        expect(slaves[0].trace).to be == @trace
        expect(slaves[1].trace).to be == @trace
        expect(TransactionSlave.where(ticket_master: 10005, trace:@trace2)).to be_empty
      end
    end
  end
  describe API::V1::APITransactionsCopy do
    context 'POST' do
      it 'Hedging - Restrict Magic Number' do
        Current.user = @user
        account = Account.find_by(name: 5634787)
        expect(account.orders.where(content_id:483857785).count).to be == 1

        Account.find_by(name: 5647753).update(magics_accept: 20000)
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:483857785)
        transaction = order.transactions.first
        expect(order.state).to be == "executed"
        expect(order.transactions.count).to be == 1
        expect(transaction.state).to be == "executed"
        expect(order.slaves.count).to be == 2
        slave1 = order.slaves.first
        slave2 = order.slaves.last
        expect(slave1.id).to be == 4
        expect(slave2.id).to be == 5
        expect(slave1.state).to be == "pending"
        expect(slave2.state).to be == "pending"
        transaction.close
        expect(transaction.state).to be == "closed"
        expect(order.state).to be == "closed"

      end
 
      it 'Hedging - Restrict Magic Number' do
        account = Account.find_by(name: 5634787)
        # @transaction = account.orders.find_by(content_id:483857785).transactions.first
        message = Message::Metatrader.create(content: nil, content_at: Time.zone.now, store: @trace.store, trace_ids:@trace.id)
        message.update_columns(state: "executed")
        if message.execute
          body "OK|OK|OK"
        else
          content_error = "Message::Metatrader ##{message.try(:id)} cannot executed - Account Name #{account.try(:name)}"
          account.loggings.create(content:content_error, state: "ERROR", changeset: message.try(:errors).try(:full_messages))
        end
        # puts Logging.last.content
        expect(Logging.last.state).to be == "ERROR"
      end
    end
  end
end    