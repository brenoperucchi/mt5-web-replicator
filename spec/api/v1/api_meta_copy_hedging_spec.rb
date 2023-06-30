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
      params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
  end

  describe API::V1::APITransactionsCopy do
    context 'Create and Restrict Transaction' do
      it 'Restrict Magic Number' do 
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"{\"ticket_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        orders = Order.where(content_id:10000002)     
        expect(orders.count).to be == 1      
      end
    end
  end
  describe API::V1::APITransactionsCopy, focus:true do
    context 'Create and Restrict Transaction' do
      it 'Restrict Magic Number' do 
        @account_copy.update(magics_accept: "2000 2001")
        expect(@account_copy.magics_accept).to be == "2000 2001"
        open_at = Time.zone.now.to_i.to_s
        open_at = open_at + ".00000000"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
        params: {"orders"=>"{\"ticket_id\":2001,\"price\":14946.46000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":2001,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] E$|B 0.20\",\"open_at\":\"1644417000\",\"state_meta\":null}//{\"ticket_id\":2000,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":2000,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}//{\"ticket_id\":2002,\"price\":2066.75000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":2002,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 2.00\",\"open_at\":\"1644420708\",\"state_meta\":null}//{\"ticket_id\":334181440,\"price\":2073.05000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] E$|S 1.00\",\"open_at\":\"1644420853\",\"state_meta\":null}//{\"ticket_id\":334185075,\"price\":14926.43000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] N$|B 0.40\",\"open_at\":\"1644421440\",\"state_meta\":null}//{\"ticket_id\":334186108,\"price\":2072.97000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":0,\"magicnumber\":701,\"symbol\":\"UsaRus\",\"comment\":\"VLL[3BE] E$|B 1.00\",\"open_at\":\"1644421560\",\"state_meta\":null}//{\"ticket_id\":334190820,\"price\":2069.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 3.00\",\"open_at\":\"1644422374\",\"state_meta\":null}//{\"ticket_id\":334196413,\"price\":14871.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] E$|S 0.20\",\"open_at\":\"1644423600\",\"state_meta\":null}//{\"ticket_id\":334197255,\"price\":2072.80000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 4.00\",\"open_at\":\"1644423815\",\"state_meta\":null}//{\"ticket_id\":334197268,\"price\":14895.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.40\",\"open_at\":\"1644423816\",\"state_meta\":null}//{\"ticket_id\":334197995,\"price\":14918.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.60\",\"open_at\":\"1644423961\",\"state_meta\":null}//{\"ticket_id\":334198079,\"price\":2075.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 5.00\",\"open_at\":\"1644423970\",\"state_meta\":null}//{\"ticket_id\":334198080,\"price\":2075.90000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] N$|S 2.00\",\"open_at\":\"1644423970\",\"state_meta\":null}//{\"ticket_id\":334198351,\"price\":113000.00000000,\"volume\":1.00000000,\"stop_loss\":111760.00000000,\"take_profit\":113230.00000000,\"type\":0,\"magicnumber\":705,\"symbol\":\"Bra50\",\"comment\":\"VLL[847] E$|B 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//{\"ticket_id\":334198352,\"price\":112980.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] E$|S 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//{\"ticket_id\":334199527,\"price\":14940.05000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.80\",\"open_at\":\"1644424361\",\"state_meta\":null}//{\"ticket_id\":334199528,\"price\":113180.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] N$|S 2.00\",\"open_at\":\"#{open_at}\",\"timezone\":0,time\"state_meta\":null}"}
        expect(Order.all.count).to be == 18
        expect(Order.error.count).to be == 15
        expect(Order.executed.count).to be == 2
        expect(Order.closed.count).to be == 1
        
        expect(Transaction.all.count).to be == 18
        expect(Transaction.error.count).to be == 15
        expect(Transaction.executed.count).to be == 2
        expect(Transaction.closed.count).to be == 0
        expect(Transaction.closed_info.count).to be == 1

        expect(TransactionSlave.all.count).to be == 6
        expect(TransactionSlave.error.count).to be == 0
        expect(TransactionSlave.executed.count).to be == 0
        expect(TransactionSlave.closed.count).to be == 0
        expect(TransactionSlave.pending.count).to be == 4
        expect(TransactionSlave.remove.count).to be == 0
        expect(TransactionSlave.deleted.count).to be == 2

        order = Order.where(content_id:2002).take
        expect(order.content_id).to be == "2002"
        expect(order.transactions.find_by(account:@account_copy).ticket).to be == "2002"
        expect(order.transactions.find_by(account:@account_copy).state).to be == "error"
        expect(order.transactions.count).to be == 1
        expect(order.slaves.count).to be == 0
        expect(order.state).to be == "error"
      end
    end
    
    context 'POST' do
      it 'Hedging - Should Restrict Order by Magic Number On Copy Account' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 5647753).update(magics_accept: "20000")
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"{\"ticket_id\":10000003,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:10000003)
        @transaction = order.transactions.first
        expect(@transaction.loggings.count).to be == 2
        expect(@transaction.state).to be == "error"
        expect(@transaction.order.state).to be == "error"
        expect(order.state).to be == "error"
        expect(order.slaves.count).to be == 0
      end
    end

    context 'POST' do
      it 'Hedging - Should Not Restrict Order by Magic Number On Copy Account' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 5647753).update(magics_accept: "20001")
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"{\"ticket_id\":10000004,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:10000004)
        @transaction = order.transactions.first
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"
        expect(order.state).to be == "executed"
        expect(order.slaves.count).to be == 2
      end
    end

    context 'POST' do
      it 'Hedging - Should Restrict Order by Magic Number On Trace' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Trace.find(1).update(magics_accept: "20001")
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"{\"ticket_id\":10000005,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20000,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:10000005)
        @transaction = order.transactions.first
        expect(@transaction.loggings.count).to be == 2
        expect(@transaction.state).to be == "error"
        expect(@transaction.order.state).to be == "error"
        expect(order.state).to be == "error"
        expect(order.slaves.count).to be == 0
      end
    end

    context 'POST' do
      it 'Hedging - Should Restrict Order by Magic Number On Trace' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Trace.find(1).update(magics_accept: "20001")
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"{\"ticket_id\":10000006,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20000,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:10000006)
        @transaction = order.transactions.first
        expect(@transaction.loggings.count).to be == 2
        expect(@transaction.state).to be == "error"
        expect(@transaction.order.state).to be == "error"
        expect(order.state).to be == "error"
        expect(order.slaves.count).to be == 0
      end
    end
    
    context 'POST' do
      it 'Hedging - Restrict Magic Number' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 5647753).update(magics_accept: "20000")
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
        params: {"orders"=>"{\"ticket_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":20001,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:10000002)
        @transaction = order.transactions.first
        expect(@transaction.loggings.count).to be == 2
        expect(@transaction.state).to be == "error"
        expect(@transaction.order.state).to be == "error"
        expect(order.state).to be == "error"
        expect(order.slaves.count).to be == 0
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
        expect(@slave.master.state).to be == "closed_info"
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
        expect(@slave_1.master.state).to be == "closed_info"
        expect(@slave_2.master.state).to be == "closed_info"
        expect(response.status).to be == 201
      end

      it 'Hedging - Remove first transaction and add another transaction' do 
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"{\"ticket_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
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
          params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//{\"ticket_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}",
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
          params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//{\"ticket_id\":10000002,\"price\":1.13473000,\"lot\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"HEDGING"}
        @account = Account.find_by(name: 5634787)
        @transaction = @account.orders.find_by(content_id:10000002).transactions.first
        @slave = @transaction.slaves.find_by(ticket_master: 10000002)
        expect(@account.orders.count).to be == 2
        expect(@slave.order.content_id).to be == "10000002"
        expect(@slave.order.id).to be == 26
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
        expect(@slave.master.state).to be == "closed_info"
        expect(@order1.id).to be == 1
        expect(@order1.state).to be == "closed"


        expect(@slave2.ticket_master).to be == "10000001"
        expect(@transaction2.ticket).to be == "10000001"
        expect(@slave2.state).to be == "deleted"
        expect(@slave2.master.state).to be == "closed_info"
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