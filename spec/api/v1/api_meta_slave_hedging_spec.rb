# 334199527
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
    @account_copy = create(:account, :copy, store: @store, customer:@customer,meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @ticket_master = 10000001
    
    open_at = Time.zone.now.to_i.to_s
    @open_at = open_at + ".00000000"
    post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
      params: {"orders"=>"
        {\"ticket_id\":334171133,\"price\":14946.46000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] E$|B 0.20\",\"open_at\":\"1644417000\",\"state_meta\":null}//
        {\"ticket_id\":334171235,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}//
        {\"ticket_id\":334179884,\"price\":2066.75000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 2.00\",\"open_at\":\"1644420708\",\"state_meta\":null}//
        {\"ticket_id\":334181440,\"price\":2073.05000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] E$|S 1.00\",\"open_at\":\"1644420853\",\"state_meta\":null}//
        {\"ticket_id\":334185075,\"price\":14926.43000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] N$|B 0.40\",\"open_at\":\"1644421440\",\"state_meta\":null}//
        {\"ticket_id\":334186108,\"price\":2072.97000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":0,\"magicnumber\":701,\"symbol\":\"UsaRus\",\"comment\":\"VLL[3BE] E$|B 1.00\",\"open_at\":\"1644421560\",\"state_meta\":null}//
        {\"ticket_id\":334190820,\"price\":2069.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 3.00\",\"open_at\":\"1644422374\",\"state_meta\":null}//
        {\"ticket_id\":334196413,\"price\":14871.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] E$|S 0.20\",\"open_at\":\"1644423600\",\"state_meta\":null}//
        {\"ticket_id\":334197255,\"price\":2072.80000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 4.00\",\"open_at\":\"1644423815\",\"state_meta\":null}//
        {\"ticket_id\":334197268,\"price\":14895.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.40\",\"open_at\":\"1644423816\",\"state_meta\":null}//
        {\"ticket_id\":334197995,\"price\":14918.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.60\",\"open_at\":\"1644423961\",\"state_meta\":null}//
        {\"ticket_id\":334198079,\"price\":2075.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 5.00\",\"open_at\":\"1644423970\",\"state_meta\":null}//
        {\"ticket_id\":334198080,\"price\":2075.90000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] N$|S 2.00\",\"open_at\":\"1644423970\",\"state_meta\":null}//
        {\"ticket_id\":334198351,\"price\":113000.00000000,\"volume\":1.00000000,\"stop_loss\":111760.00000000,\"take_profit\":113230.00000000,\"type\":0,\"magicnumber\":705,\"symbol\":\"Bra50\",\"comment\":\"VLL[847] E$|B 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//
        {\"ticket_id\":334198352,\"price\":112980.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] E$|S 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//
        {\"ticket_id\":334199527,\"price\":14940.05000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.80\",\"open_at\":\"1644424361\",\"state_meta\":null}//
        {\"ticket_id\":334199528,\"price\":113180.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] N$|S 2.00\",\"open_at\":\"#{@open_at}\",\"timezone\":0,time\"state_meta\":null}"}
    end

  describe API::V1::APITransactionsCopy do
    context 'POST' do
      it 'Restrict Magic Number' do 
        @account1.update(magics_accept: "2000")
        @account2.update(magics_accept: "2001")
        expect(@account1.magics_accept).to be == "2000"
        expect(@account2.magics_accept).to be == "2001"
        open_at = Time.zone.now.to_i.to_s
        open_at = open_at + ".00000000"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
        params: {"orders"=>"
            {\"ticket_id\":2000,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":2000,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}//
            {\"ticket_id\":2001,\"price\":14946.4600000,\"volume\":0.20000000,\"stop_loss\":14782.0500000,\"take_profit\":14976.3500000,\"type\":0,\"magicnumber\":2001,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] E$|B 0.20\",\"open_at\":\"1644417000\",\"state_meta\":null}//
            {\"ticket_id\":2002,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":2000,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}"
          }
        expect(Order.all.count).to be == 20
        expect(Order.error.count).to be == 0
        expect(Order.executed.count).to be == 3
        expect(Order.closed.count).to be == 17
        
        expect(Transaction.all.count).to be == 20
        expect(Transaction.error.count).to be == 0
        expect(Transaction.executed.count).to be == 3
        expect(Transaction.closed.count).to be == 0
        expect(Transaction.closed_info.count).to be == 17

        expect(TransactionSlave.all.count).to be ==40
        expect(TransactionSlave.error.count).to be == 3
        expect(TransactionSlave.executed.count).to be == 0
        expect(TransactionSlave.closed.count).to be == 0
        expect(TransactionSlave.pending.count).to be == 3
        expect(TransactionSlave.remove.count).to be == 0
        expect(TransactionSlave.deleted.count).to be == 34

        order = Order.where(content_id:2001).take
        expect(order.content_id).to be == 2001
        expect(order.transactions.find_by(ticket:"2001").state).to be == "executed"
        expect(order.slaves.find_by(account:@account1).ticket_master).to be == "2001"
        expect(order.slaves.find_by(account:@account2).ticket_master).to be == "2001"
        expect(order.slaves.find_by(account:@account1).state).to be == "error"
        expect(order.slaves.find_by(account:@account2).state).to be == "pending"
        expect(order.slaves.find_by(account:@account1).account.magics_accept).to be == "2000"
        expect(order.slaves.find_by(account:@account2).account.magics_accept).to be == "2001"
        expect(order.slaves.find_by(account:@account1).loggings.last.state).to be == "ERROR"
        expect(order.slaves.find_by(account:@account2).loggings.last).to be == nil
        expect(order.state).to be == "executed"
        expect(order.transactions.count).to be == 1
        expect(order.slaves.count).to be == 2
        expect(order.transactions.first.state).to be == "executed"
      end
    end

    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        post '/api/v1/transactions/request/entire/signal_slave/1_62/5634788/HEDGING'
        expect(response.body).to be == "1|334199527|0|1|2|20001|1|14940.05|0.2|15036.41|14843.06|pending|UsaTec|0|0|334199527|0/1|334197995|0|1|4|20001|2|14918.81|0.2|15036.41|14843.06|pending|UsaTec|0|0|334197995|0/1|334197268|0|1|6|20001|3|14895.81|0.2|15036.41|14843.06|pending|UsaTec|0|0|334197268|0/1|334196413|0|1|8|20001|4|14871.81|0.2|15036.41|14843.06|pending|UsaTec|0|0|334196413|0/0|334185075|0|1|10|20001|5|0|0.2|14782.05|14976.35|pending|UsaTec|0|0|334185075|0/0|334171133|0|1|12|20001|6|0|0.2|14782.05|14976.35|pending|UsaTec|0|0|334171133|0/1|334198080|0|1|14|20001|7|2075.9|1.0|2091.0|2053.0|pending|UsaRus|0|0|334198080|0/1|334198079|0|1|16|20001|8|2075.95|1.0|2086.3|2059.47|pending|UsaRus|0|0|334198079|0/1|334197255|0|1|18|20001|9|2072.8|1.0|2086.3|2059.47|pending|UsaRus|0|0|334197255|0/1|334190820|0|1|20|20001|10|2069.95|1.0|2086.3|2059.47|pending|UsaRus|0|0|334190820|0/0|334186108|0|1|22|20001|11|0|1.0|2050.17|2077.12|pending|UsaRus|0|0|334186108|0/1|334181440|0|1|24|20001|12|2073.05|1.0|2091.0|2053.0|pending|UsaRus|0|0|334181440|0/1|334179884|0|1|26|20001|13|2066.75|1.0|2086.3|2059.47|pending|UsaRus|0|0|334179884|0/1|334171235|0|1|28|20001|14|2063.6|1.0|2086.3|2059.47|pending|UsaRus|0|0|334171235|0/1|334199528|0|1|30|20001|15|113180.0|1.0|114230.0|112760.0|pending|Bra50|0|0|334199528|0/1|334198352|0|1|32|20001|16|112980.0|1.0|114230.0|112760.0|pending|Bra50|0|0|334198352|0/0|334198351|0|1|34|20001|17|0|1.0|111760.0|113230.0|pending|Bra50|0|0|334198351|0"
        @account1 = Account.find_by_name("5634787")  
        @slaves = @account1.slaves.where(ticket_master:334199527)
        expect(@slaves.first.stop_loss).to be == "15036.41"
        expect(@slaves.first.take_profit).to be == "14843.06"

        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/HEDGING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'OPEN', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'334199552', 'deal_ticket':'290610221', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'334199527', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 334199527'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"HEDGING"}
        @account1 = Account.find_by_name("5634787")  
        @slaves = @account1.slaves.where(ticket_master:334199527)
        expect(@slaves.count).to be == 1
        expect(@account1.slaves.count).to be == 17
        expect(@account1.slaves.pending.count).to be == 16
        expect(@account1.slaves.executed.count).to be == 1
        expect(@slaves.first.stop_loss).to be == "15036.41"
        expect(@slaves.first.take_profit).to be == "14843.06"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
          params: {"orders"=>"{\"ticket_id\":334171133,\"price\":14946.46000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] E$|B 0.20\",\"open_at\":\"1644417000\",\"state_meta\":null}//{\"ticket_id\":334171235,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}//{\"ticket_id\":334179884,\"price\":2066.75000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 2.00\",\"open_at\":\"1644420708\",\"state_meta\":null}//{\"ticket_id\":334181440,\"price\":2073.05000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] E$|S 1.00\",\"open_at\":\"1644420853\",\"state_meta\":null}//{\"ticket_id\":334185075,\"price\":14926.43000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] N$|B 0.40\",\"open_at\":\"1644421440\",\"state_meta\":null}//{\"ticket_id\":334186108,\"price\":2072.97000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":0,\"magicnumber\":701,\"symbol\":\"UsaRus\",\"comment\":\"VLL[3BE] E$|B 1.00\",\"open_at\":\"1644421560\",\"state_meta\":null}//{\"ticket_id\":334190820,\"price\":2069.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 3.00\",\"open_at\":\"1644422374\",\"state_meta\":null}//{\"ticket_id\":334196413,\"price\":14871.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] E$|S 0.20\",\"open_at\":\"1644423600\",\"state_meta\":null}//{\"ticket_id\":334197255,\"price\":2072.80000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 4.00\",\"open_at\":\"1644423815\",\"state_meta\":null}//{\"ticket_id\":334197268,\"price\":14895.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.40\",\"open_at\":\"1644423816\",\"state_meta\":null}//{\"ticket_id\":334197995,\"price\":14918.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.60\",\"open_at\":\"1644423961\",\"state_meta\":null}//{\"ticket_id\":334198351,\"price\":113000.00000000,\"volume\":1.00000000,\"stop_loss\":111760.00000000,\"take_profit\":113230.00000000,\"type\":0,\"magicnumber\":705,\"symbol\":\"Bra50\",\"comment\":\"VLL[847] E$|B 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//{\"ticket_id\":334198352,\"price\":112980.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] E$|S 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//{\"ticket_id\":334199527,\"price\":14940.05000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.80\",\"open_at\":\"1644424361\",\"state_meta\":\"modify\"}"}
        @account1 = Account.find_by_name("5634787")  
        @slaves = @account1.slaves.where(ticket_master:334199527)
        expect(@slaves.count).to be == 1
        expect(@slaves.first.state).to be == "executed"
        expect(@slaves.first.stop_loss).to be == "2050.17"
        expect(@slaves.first.take_profit).to be == "2077.12"

      end
    end

    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do
        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/HEDGING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'OPEN', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'334199552', 'deal_ticket':'290610221', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'334199527', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 334199527'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"HEDGING"}
        @account1 = Account.find_by_name("5634787")  
        @account2 = Account.find_by_name("5634788")  
        # @slaves2 = @account1.slaves.where(ticket_master:334199527)
        # @slaves2 = @account2.slaves.where(ticket_master:334199527)
        expect(@account1.slaves.count).to be == 17
        expect(@account2.slaves.count).to be == 17
        expect(@account1.orders.count).to be == 17
        expect(@account1.slaves.find_by(ticket_master: 334199527).state).to be == "executed"
        expect(@account2.slaves.find_by(ticket_master: 334199527).state).to be == "pending"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_42", "action"=>"orders", "account_id"=>"3000033103", "account_mode"=>"HEDGING"}
        expect(@account1.slaves.find_by(ticket_master: 334199527).state).to be == "remove"
        expect(@account2.slaves.find_by(ticket_master: 334199527).state).to be == "deleted"

      end
    end    
    context 'POST' do
      it 'Hedging - Verify Slave should created in one Trace even inserted two traces with same copy' do

        @trace2 = create(:trace, :copy2, store: @store)
        @account_copy.update(trace_ids: [1,2])
        @account1.update(trace_ids: [1,2])
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
          params: {"orders"=>"
            {\"ticket_id\":1003,\"price\":113180.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] N$|S 2.00\",\"open_at\":\"#{@open_at}\",\"timezone\":0,time\"state_meta\":null}"
          }

        trace = Trace.find_by(name: "SignalCopy2")
        expect(trace.accounts.count).to be == 2

        account_copy = Account.find_by(name: 5647753)
        expect(account_copy.traces.count).to be == 2
        account_slave = Account.find_by(name: 5634787)
        expect(account_slave.traces.count).to be == 2

        slaves = TransactionSlave.where(ticket_master: 1003)
        expect(slaves.count).to be == 2
        expect(slaves.first.account_id).to be == 2
        expect(slaves.last.account_id).to be  == 3
        expect(slaves.first.account_id).not_to be == slaves.last.account_id
      end
    end
    
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_42", "action"=>"orders", "account_id"=>"3000033103", "account_mode"=>"HEDGING"}
        expect(Account.find_by(name:5634787).slaves.last.state).to be == "deleted"
        # expect(@account1.slaves.last.state).to be == "deleted"
        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/HEDGING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'NOSLTP', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'0', 'deal_ticket':'0', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'334199527', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 334199527'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"HEDGING"}

      end
    end

    context 'POST' do
      it 'Hedging - Check Automattically' do
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING',
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_42", "action"=>"orders", "account_id"=>"3000033103", "account_mode"=>"HEDGING"}
        expect(Account.find_by(name:5634787).slaves.last.state).to be == "deleted"
        # expect(@account1.slaves.last.state).to be == "deleted"
        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/HEDGING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'NOSLTP', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'0', 'deal_ticket':'0', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'334199527', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 334199527'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"HEDGING"}

      end
    end
  end
end