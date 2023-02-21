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
    context 'Control Instrument'do #, focus:true do
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
      it 'Trace - Create order all traces'do #, focus:true do
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
      
      it 'Trace - One trace disable'do #, focus:true do
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