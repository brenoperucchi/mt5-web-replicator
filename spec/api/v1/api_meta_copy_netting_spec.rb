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
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'netting')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'netting')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'netting')
    
    open_at = Time.zone.now.to_i
    post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
    params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"#{open_at}\",\"timezone\":0,time\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
  end

  describe API::V1::APITransactionsCopy do
    context 'POST' do
      it 'Netting - Verify account 5634787' do
        account = Account.find_by(name: 5634787)
        order = account.orders.find_by(content_id: 10000001)
        @transaction = order.transactions.find_by(ticket: 10000001)
        @slave = order.slaves.find_by(ticket_master: 10000001, account:account)
        expect(@account1.state).to be == "enable"
        expect(@account1.kind).to be == "slave"
        expect(@transaction.ticket).to be == 10000001 
        expect(@slave.ticket_master).to be == 10000001 
        expect(@transaction.state).to be == "executed"
        expect(@transaction.trace.name_id).to be == "20001"
        expect(@slave.state).to be == "pending"
        expect(@slave.seconds_ago).to be <= 30
        expect(@slave.seconds_ago).to be >= 0
        @slave.execute
        expect(@slave.state).to be == "executed"
        expect(response.status).to eq(201)
      end

      it 'Netting - Verify account 5634788' do
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id: 10000001).transactions.first
        @slave = account.orders.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001, account:account)
        expect(@account2.state).to be == "enable"
        expect(@account2.kind).to be == "slave"

        expect(@transaction.ticket).to be == 10000001 
        expect(@slave.ticket_master).to be == 10000001 
        expect(@transaction.state).to be== "executed"
        expect(@slave.state).to be == "pending"
        @slave.execute
        expect(@slave.state).to be == "executed"
        expect(response.status).to eq(201)
      end

      it 'Netting - Post Remove All Orders' do #, focus:true do
        account = Account.find_by(name: 5634788)
        @order = account.orders.find_by(content_id:10000001)
        @transaction = account.orders.find_by(content_id: 10000001).transactions.first
        @slave = account.orders.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001, account:account)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        @transaction = account.orders.find_by(content_id:10000001)
        @slave =  @order.slaves.find_by(ticket_master: 10000001, account: account)
        expect(@slave.trace.name_id).to be == "20001"
        account_87 = Account.find_by(name: 5634787)
        @slave2 = account_87.slaves.find_by(ticket_master: 10000001)
        expect(account.orders.count).to be == 1
        expect(account.orders.count).to be <= 2
        expect(account.slaves.count).to be <= 2
        expect(account.slaves.count).to be == 1
        expect(account.slaves.count).not_to be == 2
        expect(@transaction.state).to be == "closed"
        expect(@slave.state).to be == "remove"
        expect(@order.state).to be == "executed"
        @slave.close
        expect(@slave.state).to be == "closed"
        expect(@slave.master.state).to be == "closed_info"
        @order.slaves.last.close
        expect(@slave.master.state).to be == "closed_info"
        @slave2.close
        @transaction.close
        @order = account.orders.find_by(content_id:10000001)
        expect(@order.state).to be == "closed"
        expect(response.status).to eq(201)

        # @order = @trace.orders.find_by(message_id: 723517440)
        # expect(@order.kind).to be == "order"
      end      

      it 'Netting - Remove Transaction should be deleted on non executed t-slaves' do
        account_87 = Account.find_by(name: 5634787)
        account_88 = Account.find_by(name: 5634788)
        @order = @account_copy.orders.find_by(content_id:10000001)
        @slave_1 = account_87.orders.find_by(content_id:10000001).slaves.find_by(ticket_master: 10000001)
        @slave_1.execute
        expect(@slave_1.state).to be == "executed"
        @slave_2 = account_88.orders.find_by(content_id:10000001).slaves.find_by(ticket_master: 10000001)
        expect(@slave_2.master.state).to be == "executed"
        expect(@order.state).to be == "executed"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        @slave_1 = Order.find_by(content_id:10000001).slaves.find_by(ticket_master: 10000001, account: account_87)
        @slave_2 = Order.find_by(content_id:10000001).slaves.find_by(ticket_master: 10000001, account: account_88)
        @order = @account_copy.orders.find_by(content_id:10000001)
        expect(@slave_1.state).to be == "remove"
        expect(@slave_2.state).to be == "deleted"
        expect(@slave_1.master.state).to be == "closed_info"
        expect(@slave_2.master.state).to be == "closed_info"
        expect(@order.state).to be == "closed"
        expect(response.status).to eq(201)
      end

      it 'Netting - Remove first transactiorder.on and add another transaction' do 
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id: 10000001).transactions.first
        @slave = account.orders.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001, account:account)
        @slave.execute
        open_at = Time.now.utc.to_i
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"#{open_at}\",\"timezone\":3,time\"state_meta\":\"\"}", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        @order1 = account.orders.find_by(content_id:10000001)
        @order2 = account.orders.find_by(content_id:10000002)
        @transaction1 = @order1.transactions.find_by(ticket: 10000001)
        @transaction2 = @order2.transactions.find_by(ticket: 10000002)
        @slave11 = @order1.slaves.where(ticket_master: 10000001).first
        @slave12 = @order1.slaves.where(ticket_master: 10000001).last
        @slave21 = @order2.slaves.where(ticket_master: 10000002).first
        @slave22 = @order2.slaves.where(ticket_master: 10000002).last

        expect(@slave21.id).to be == 3
        expect(@slave22.id).to be == 4
        expect(@slave21.ticket_master).to be == 10000002
        expect(@slave22.ticket_master).to be == 10000002
        expect(@slave21.seconds_ago).to be <= 30
        expect(@slave21.seconds_ago).to be >= 0

        expect(@order1.state).to be == "closed"
        expect(@order2.state).to be == "executed"
        expect(@slave11.account.name).to be == "5634787"
        expect(@slave12.account.name).to be == "5634788"
        expect(@slave11.ticket_master).to be == 10000001
        expect(@slave12.ticket_master).to be == 10000001
        expect(@slave11.state).to be == "deleted"
        expect(@slave12.state).to be == "remove"
        expect(@slave21.state).to be == "pending"

        @slave21.execute
        expect(@slave21.state).to be == "executed"
        # @slave22.execute
        @slave21 = @transaction2.slaves.where(ticket_master: 10000002).first
        @slave22 = @transaction2.slaves.where(ticket_master: 10000002).last

        expect(@slave21.state).to be == "executed"
        expect(@slave22.state).not_to be == "executed"
        
        expect(@slave21.ticket_master).to be == 10000002
        expect(@slave22.ticket_master).to be == 10000002
        expect(@slave21.state).to be == "executed"


        expect(account.orders.count).to be == 2
        expect(@store.orders.count).to be == 2
        expect(@store.orders.first.id).to be == 1
        expect(@store.orders.first.slaves.count).to be == 2
        expect(@store.orders.last.id).to be == 2
        expect(@store.orders.last.slaves.count).to be == 2

        expect(@slave11.take_profit).to be == "0.0"
        expect(@slave11.symbol).to be == "EURUSD"
        expect(@slave11.stop_loss).to be == "0.0"

        expect(@slave11.state).to be == "deleted"
        expect(@slave12.state).to be == "remove"
        @slave22 = account.orders.find_by(content_id:10000002).slaves.last
        expect(@slave22.id).to be == 4
        expect(@slave22.state).to be == "pending"
        expect(@slave22.symbol).to be == "USDCAD"
        expect(@slave22.stop_loss).to be == "1.1"
        expect(@slave22.take_profit).to be == "1.2"

        # expect(@slave.closed_at).to be_nil
      end      

      it 'Netting - Remove first transaction and add another transaction'do #, focus:true do
        account = Account.find_by(name: 5634788)
        # @transaction = account.orders.find_by(content_id: 10000001).transactions.first
        @order = @store.orders.find_by(content_id: 10000001)
        @slave = @order.slaves.find_by(ticket_master: 10000001)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}        
        @slave1 = Transaction.find_by(ticket:10000001).slaves.find_by(ticket_master: 10000001)
        
        expect(account.orders.count).to be == 1
        expect(@store.orders.count).to be == 1        
        expect(@slave1.take_profit).to be == "1.2"
        expect(@slave1.stop_loss).to be == "1.1"

        # @slave1.close
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
          "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        # @slave1 = @store.orders.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001)
        @transaction = Transaction.find_by(ticket:10000001)

        @slave1 = Order.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001)
        expect(@transaction.state).to be == "closed_info"
        expect(@slave1.state).to be == "deleted"
        @slave2 = Transaction.find_by(ticket:10000002).slaves.find_by(ticket_master: 10000002)
        expect(@slave2.state).to be == "pending"
      end

      it 'Netting - Modify Position first transaction and add another order' do
        account = Account.find_by(name: 5634788)
        @order = account.orders.find_by(content_id:10000001)
        @transaction = @order.transactions.find_by(ticket: 10000001)
        @slave = @order.slaves.find_by(ticket_master: 10000001, account: account)

        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"volume\":0.03000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//
                              {\"ticket_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
                "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        @slave = account.orders.find_by(content_id:10000001).slaves.find_by(ticket_master: 10000001)
        @orders = @store.orders
        expect(@orders.count).to be == 2

        expect(@orders.first.content_id).to be == 10000001
        expect(@orders.last.content_id).to be == 10000002
        expect(@orders.first.id).to be == 1
        expect(@orders.last.id).to be == 4
        expect(@orders.first.transactions.first.ticket).to be == 10000001
        expect(@orders.first.transactions.last.ticket).to be == 10000001
        expect(account.orders.count).to be == 2
        expect(account.slaves.count).to be == 2
        expect(account.slaves.count).not_to be == 1
        expect(account.slaves.count).not_to be == 3
        
        expect(@order.transactions.count).to be == 1
        expect(@order.slaves.count).to be == 2

        expect(@transaction.slaves.count).to be == 2
        expect(@order.slaves.count).to be == 2
        expect(@transaction.state).to be == "executed"
        expect(@slave.symbol).to be == "EURUSD"
        expect(@slave.take_profit).not_to be == "0.0"
        expect(@slave.stop_loss).not_to be == "0.0"
        expect(@slave.take_profit).to be == "1.2"
        expect(@slave.stop_loss).to be == "1.1"
        expect(@slave.lot).to be == "0.03"
        @slave.remove
        expect(@slave.state).to be == "deleted"
        expect(@slave.closed_at).to be_nil
        @slave.close
        expect(@slave.closed_at).to be_nil
        expect(@slave.state).to be == "deleted"
        expect(@slave.master.state).to be == "executed"
        expect(response.status).to eq(201)
        @slave2 = account.orders.find_by(content_id: 10000002).slaves.find_by(ticket_master: 10000002)
        expect(@slave2.state).to be == "pending"
        @slave2.execute
        expect(@slave2.state).to be == "executed"
        expect(@slave2.symbol).to be == "USDCAD"
        expect(@slave2.lot).to be == "0.02"
        expect(@slave2.closed_at).to be_nil
        @slave2.close
        expect(@slave2.state).to be == "closed"
        expect(@slave2.closed_at).not_to be_nil
        expect(@slave2.master.state).to be == "executed"
        @slave = account.orders.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001, account:account)
        expect(@slave.master.state).to be == "executed"

      end

      it 'Netting - Modify Position first transaction and add another order' do
        account = Account.find_by(name: 5634787)
        @transaction = account.orders.find_by(content_id: 10000001).transactions.first
        @slave = account.orders.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001, account:account)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//
                              {\"ticket_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}//
                              {\"ticket_id\":10000003,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"USDCAD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}",
                               "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        transaction1 = Account.find_by(name: 5634787).orders.find_by(content_id: 10000001)
        transaction2 = Account.find_by(name: 5634787).orders.find_by(content_id: 10000002)
        transaction3 = Account.find_by(name: 5634787).orders.find_by(content_id: 10000003)
        slave1 = transaction1.slaves.find_by(ticket_master: 10000001)
        slave2 = transaction3.slaves.find_by(ticket_master: 10000003)
        expect(transaction2).to be nil
        expect(slave1.ticket_master).to be == 10000001
        expect(slave2.ticket_master).to be == 10000003
        expect(transaction1.slaves.count).to be == 2
        expect(transaction1.slaves.count).to be == 2
        expect(transaction3.slaves.count).to be == 2
        expect(slave1.take_profit).not_to be == 0
        expect(slave1.stop_loss).not_to be == 0
        expect(slave1.take_profit).to be == "1.2"
        expect(slave1.stop_loss).to be == "1.1"
        expect(response.status).to be == 201
      end

      it 'Netting - Modify Position first transaction and add another order' do
        account = Account.find_by(name: 5634788)
        @transaction = account.orders.find_by(content_id: 10000001,).transactions.first
        @slave = Order.find_by(content_id: 10000001).slaves.find_by(ticket_master: 10000001, account:account)
        @slave.execute
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000001,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        transaction = Account.find_by(name: 5634787).orders.find_by(content_id: 10000001)
        @slave = transaction.slaves.find_by(ticket_master: 10000001, account:account)
        expect(transaction.slaves.count).to be == 2
        expect(@slave.take_profit).not_to be == 0
        expect(@slave.stop_loss).not_to be == 0
        expect(@slave.take_profit).to be == "1.2"
        expect(@slave.stop_loss).to be == "1.1"
        expect(response.status).to be == 201
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"ticket_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
        
        @slave = transaction.slaves.find_by(ticket_master: 10000001, account:account)
        expect(@slave.state).to be == "remove"
        @slave.close
        
        transaction.close
        expect(transaction.state).to be == "closed"
        
        @order = Account.find_by(name: 5634787).orders.find_by(content_id: 10000001)
        expect(@order.state).to be == "closed"
      end

    end
  end
end    