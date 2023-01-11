require 'rails_helper'

RSpec.describe API::V1::APITransactionsCopy do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @trace = create(:trace, :copy, store: @store)
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, store:@store, user:@user_admin)
    @customer = create(:customer, :customer, store:@store, user:@user_customer)
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @ticket_master = 10000001
    
    post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
    params: {"orders"=>"{\"order_id\":10000001,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
  end

  describe API::V1::APITransactionsCopy do
    context 'POST' do

      it 'Hedging - Restrict Magic Number' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 5647753).update(magics_accept: 20000)
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"{\"order_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:10000002)
        @transaction = order.transactions.first
        # @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(@transaction.loggings.count).to be == 2
        expect(@transaction.state).to be == "error"
        expect(@transaction.order.state).to be == "error"
        expect(order.state).to be == "error"
        expect(order.slaves.count).to be == 0
        # expect(account.orders.where(content_id:10000001).count).to eq(1)
        # expect(@account1.state).to be == "enable"
        # expect(@account1.kind).to be == "slave"
        # expect(@slave.ticket_master).to be == "10000001" 
        # expect(@transaction.state).to be == "executed"
        # expect(@slave.state).to be == "pending"
        # expect(@slave.seconds_ago).to be <= 30
        # expect(@slave.seconds_ago).to be >= 0

        # @slave.execute
        # expect(@slave.state).to be == "executed"
        # expect(response.status).to be == 201
      end

      it 'Hedging - Verify account 5634787' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        # @slave = account.orders.find_by(content_id:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@account1.state).to be == "enable"
        expect(@account1.kind).to be == "slave"
        expect(@transaction.ticket).to be == "10000001" 
        expect(@slave.ticket_master).to be == "10000001" 
        expect(@transaction.state).to be == "executed"
        expect(@slave.state).to be == "pending"
        expect(@slave.seconds_ago).to be <= 30
        expect(@slave.seconds_ago).to be >= 0

        @slave.execute
        expect(@slave.state).to be == "executed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Verify account 5634788' do
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(@account2.state).to be == "enable"
        expect(@account2.kind).to be == "slave"

        expect(@transaction.ticket).to be == "10000001" 
        expect(@slave.ticket_master).to be == "10000001" 
        expect(@transaction.state).to be== "executed"
        expect(@slave.state).to be == "pending"
        @slave.execute
        expect(@slave.state).to be == "executed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Post Remove All Orders' do
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(account.slaves.count).to be == 1
        expect(account.slaves.count).not_to be == 2
        expect(@transaction.state).to be == "executed"
        expect(@slave.state).to be == "remove"
        @slave.close
        expect(@slave.state).to be == "closed"
        expect(@slave.master.state).to be == "closed"
        expect(response.status).to be == 201

        # @order = @trace.orders.find_by(message_id: 723517440)
        # expect(@order.kind).to be == "order"
      end      

      it 'Hedging - Remove All Transaction executed should be deleted and not executed should be remove' do
        account_87 = Account.find_by(name: 5634787)
        account_88 = Account.find_by(name: 5634788)
        # @transaction = account_87.transactions.find_by(ticket:@ticket_master)
        @slave_1 = account_87.slaves.find_by(ticket_master: @ticket_master)
        @slave_1.execute
        expect(@slave_1.state).to be == "executed"
        @slave_2 = account_88.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave_2.state).to be == "pending"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @slave_1 = account_87.slaves.find_by(ticket_master: @ticket_master)
        @slave_2 = account_88.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave_1.state).to be == "remove"
        expect(@slave_2.state).to be == "deleted"
        expect(@slave_1.master.state).to be == "closed"
        expect(@slave_2.master.state).to be == "closed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Remove first transaction and add another transaction' do
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"{\"order_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @slave1 = account.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave1.state).to be == "remove"
        @slave2 = account.slaves.find_by(ticket_master: 10000002)
        expect(@slave2.state).to be == "pending"
        # expect(@slave.closed_at).to be_nil
      end

      it 'Hedging - Modify Position first transaction and add another order' do
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"{\"order_id\":10000001,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//{\"order_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}",
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave.state).to be == "executed"
        expect(@slave.order.state).to be == "executed"
        expect(@transaction.state).to be == "executed"

        expect(account.slaves.count).to be == 2
        expect(account.slaves.count).not_to be == 1
        expect(account.slaves.count).not_to be == 3
        expect(@transaction.slaves.count).to be == 2
        expect(@slave.take_profit).not_to be == "0.0"
        expect(@slave.stop_loss).not_to be == "0.0"
        expect(@slave.take_profit).to be == "1.2"
        expect(@slave.stop_loss).to be == "1.1"
        @slave.remove
        expect(@slave.state).to be == "remove"
        expect(@slave.closed_at).to be_nil
        @slave.close
        expect(@slave.closed_at).not_to be_nil
        expect(@slave.state).to be == "closed"
        expect(@slave.master.state).to be == "executed"
        @slave.master.close
        expect(@slave.master.state).to be == "closed"
        expect(@slave.order.state).to be == "closed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Modify Position first transaction and add another order' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"{\"order_id\":10000001,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//{\"order_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @account = Account.find_by(name: 5634787)
        @transaction = @account.orders.find_by(content_id:10000002).transactions.first
        @slave = @transaction.slaves.find_by(ticket_master: 10000002)
        expect(@account.orders.count).to be == 2
        expect(@slave.order.content_id).to be == "10000002"
        expect(@slave.order.id).to be == 5
        expect(@slave.take_profit).not_to be == 0
        expect(@slave.stop_loss).not_to be == 0
        expect(@slave.take_profit).to be == "1.2"
        expect(@slave.stop_loss).to be == "1.1"
        expect(response.status).to be == 201
      end

      it 'Hedging - Close Order' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @account = Account.find_by(name: 5634787)
        @order1 = @account.orders.find_by(content_id:10000001)
        @transaction = @order1.transactions.find_by(ticket: 10000001)
        @slave = @order1.slaves.find_by(ticket_master: 10000001, account: account)
        @account2 = Account.find_by(name: 5634788)
        @order2 = @account2.orders.find_by(content_id: 10000001)
        @transaction2 = @account2.transactions.find_by(ticket:10000001)
        @slave2 = @order2.slaves.find_by(ticket_master: 10000001, account: @account2)

        expect(@slave.ticket_master).to be == "10000001"
        expect(@transaction.ticket).to be == "10000001"
        expect(@slave.state).to be == "remove"
        expect(@slave.master.state).to be == "closed"
        expect(@order1.id).to be == 1
        expect(@order1.state).to be == "closed"


        expect(@slave2.ticket_master).to be == "10000001"
        expect(@transaction2.ticket).to be == "10000001"
        expect(@slave2.state).to be == "deleted"
        expect(@slave2.master.state).to be == "closed"
        expect(@order2.id).to be == 1
        expect(@order2.state).to be == "closed"
        # expect(@account.orders.count).to be == 2
        # expect(@transaction.orders.count).to be == 2
        # expect(@slave.order).to be == 1
        # expect(@slave.order.id).to be == 7
        # expect(@slave.order.id).to be == 7
        # expect(@slave.take_profit).not_to be == 0
        # expect(@slave.stop_loss).not_to be == 0
        # expect(@slave.take_profit).to be == "1.2"
        # expect(@slave.stop_loss).to be == "1.1"
        expect(response.status).to be == 201
      end
    end
  end
end    