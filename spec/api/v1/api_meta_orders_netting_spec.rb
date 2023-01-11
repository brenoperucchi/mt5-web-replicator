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
    @ticket_master = 10000001    
    open_at = Time.zone.now.to_i
    post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING',
    params: {"orders"=>"{\"order_id\":334171133,\"price\":14946.46000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] E$|B 0.20\",\"open_at\":\"1644417000\",\"state_meta\":null}//
                        {\"order_id\":334171235,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}//
                        {\"order_id\":334179884,\"price\":2066.75000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 2.00\",\"open_at\":\"1644420708\",\"state_meta\":null}//
                        {\"order_id\":334181440,\"price\":2073.05000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] E$|S 1.00\",\"open_at\":\"1644420853\",\"state_meta\":null}//
                        {\"order_id\":334185075,\"price\":14926.43000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] N$|B 0.40\",\"open_at\":\"1644421440\",\"state_meta\":null}//
                        {\"order_id\":334186108,\"price\":2072.97000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":0,\"magicnumber\":701,\"symbol\":\"UsaRus\",\"comment\":\"VLL[3BE] E$|B 1.00\",\"open_at\":\"1644421560\",\"state_meta\":null}//
                        {\"order_id\":334190820,\"price\":2069.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 3.00\",\"open_at\":\"1644422374\",\"state_meta\":null}//
                        {\"order_id\":334196413,\"price\":14871.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] E$|S 0.20\",\"open_at\":\"1644423600\",\"state_meta\":null}//
                        {\"order_id\":334197255,\"price\":2072.80000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 4.00\",\"open_at\":\"1644423815\",\"state_meta\":null}//
                        {\"order_id\":334197268,\"price\":14895.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.40\",\"open_at\":\"1644423816\",\"state_meta\":null}//
                        {\"order_id\":334197995,\"price\":14918.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.60\",\"open_at\":\"1644423961\",\"state_meta\":null}//
                        {\"order_id\":334198079,\"price\":2075.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 5.00\",\"open_at\":\"1644423970\",\"state_meta\":null}//
                        {\"order_id\":334198080,\"price\":2075.90000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] N$|S 2.00\",\"open_at\":\"1644423970\",\"state_meta\":null}//
                        {\"order_id\":334198351,\"price\":113000.00000000,\"volume\":1.00000000,\"stop_loss\":111760.00000000,\"take_profit\":113230.00000000,\"type\":0,\"magicnumber\":705,\"symbol\":\"Bra50\",\"comment\":\"VLL[847] E$|B 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//
                        {\"order_id\":334198352,\"price\":112980.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] E$|S 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//
                        {\"order_id\":10001,\"price\":14940.05000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.80\",\"open_at\":\"1644424361\",\"state_meta\":null}//
                        {\"order_id\":334199528,\"price\":113180.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] N$|S 2.00\",\"open_at\":\"#{open_at}\",\"timezone\":0,time\"state_meta\":null}"}
  end
  describe API::V1::APITransactionsCopy do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        post '/api/v1/transactions/request/entire/signal_slave/1_62/5634788/NETTING'
        expect(response.body).to be ==  "1|10001||1|2|20001|1|14940.05|0.2|15036.41|14843.06|pending|UsaTec|0|0|10001|0/1|334198080||1|4|20001|2|2075.9|1.0|2091.0|2053.0|pending|UsaRus|0|0|334198080|0/1|334199528||1|6|20001|3|113180.0|1.0|114230.0|112760.0|pending|Bra50|0|0|334199528|0"
        @account1 = Account.find_by_name("5634787")  
        @slaves = @account1.slaves.where(ticket_master:10001)
        expect(@slaves.first.stop_loss).to be == "15036.41"
        expect(@slaves.first.take_profit).to be == "14843.06"

        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/NETTING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'OPEN', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'334199552', 'deal_ticket':'290610221', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'10001', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 10001'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"NETTING"}
        @account1 = Account.find_by_name("5634787")  
        @slaves = @account1.slaves.where(ticket_master:10001)
        expect(@slaves.count).to be == 1
        expect(@account1.slaves.count).to be == 3
        expect(@account1.slaves.pending.count).to be == 2
        expect(@account1.slaves.executed.count).to be == 1
        expect(@slaves.first.stop_loss).to be == "15036.41"
        expect(@slaves.first.take_profit).to be == "14843.06"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING', 
          params: {"orders"=>"{\"order_id\":334171133,\"price\":14946.46000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] E$|B 0.20\",\"open_at\":\"1644417000\",\"state_meta\":null}//{\"order_id\":334171235,\"price\":2063.60000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] E$|S 1.00\",\"open_at\":\"1644417028\",\"state_meta\":null}//{\"order_id\":334179884,\"price\":2066.75000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 2.00\",\"open_at\":\"1644420708\",\"state_meta\":null}//{\"order_id\":334181440,\"price\":2073.05000000,\"volume\":1.00000000,\"stop_loss\":2091.00000000,\"take_profit\":2053.00000000,\"type\":1,\"magicnumber\":5502,\"symbol\":\"UsaRus\",\"comment\":\"VLL[61F] E$|S 1.00\",\"open_at\":\"1644420853\",\"state_meta\":null}//{\"order_id\":334185075,\"price\":14926.43000000,\"volume\":0.20000000,\"stop_loss\":14782.05000000,\"take_profit\":14976.35000000,\"type\":0,\"magicnumber\":703,\"symbol\":\"UsaTec\",\"comment\":\"VLL[7AF] N$|B 0.40\",\"open_at\":\"1644421440\",\"state_meta\":null}//{\"order_id\":334186108,\"price\":2072.97000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":0,\"magicnumber\":701,\"symbol\":\"UsaRus\",\"comment\":\"VLL[3BE] E$|B 1.00\",\"open_at\":\"1644421560\",\"state_meta\":null}//{\"order_id\":334190820,\"price\":2069.95000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 3.00\",\"open_at\":\"1644422374\",\"state_meta\":null}//{\"order_id\":334196413,\"price\":14871.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] E$|S 0.20\",\"open_at\":\"1644423600\",\"state_meta\":null}//{\"order_id\":334197255,\"price\":2072.80000000,\"volume\":1.00000000,\"stop_loss\":2086.30000000,\"take_profit\":2059.47000000,\"type\":1,\"magicnumber\":702,\"symbol\":\"UsaRus\",\"comment\":\"VLL[E82] N$|S 4.00\",\"open_at\":\"1644423815\",\"state_meta\":null}//{\"order_id\":334197268,\"price\":14895.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.40\",\"open_at\":\"1644423816\",\"state_meta\":null}//{\"order_id\":334197995,\"price\":14918.81000000,\"volume\":0.20000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.60\",\"open_at\":\"1644423961\",\"state_meta\":null}//{\"order_id\":334198351,\"price\":113000.00000000,\"volume\":1.00000000,\"stop_loss\":111760.00000000,\"take_profit\":113230.00000000,\"type\":0,\"magicnumber\":705,\"symbol\":\"Bra50\",\"comment\":\"VLL[847] E$|B 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//{\"order_id\":334198352,\"price\":112980.00000000,\"volume\":1.00000000,\"stop_loss\":114230.00000000,\"take_profit\":112760.00000000,\"type\":1,\"magicnumber\":706,\"symbol\":\"Bra50\",\"comment\":\"VLL[B29] E$|S 1.00\",\"open_at\":\"1644424020\",\"state_meta\":null}//{\"order_id\":10001,\"price\":14940.05000000,\"volume\":1.00000000,\"stop_loss\":2050.17000000,\"take_profit\":2077.12000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.80\",\"open_at\":\"1644424361\",\"state_meta\":\"modify\"}"}
        @account1 = Account.find_by_name("5634787")  
        @slaves = @account1.slaves.where(ticket_master:10001)
        expect(@slaves.count).to be == 1
        expect(@slaves.first.state).to be == "executed"
        expect(@slaves.first.stop_loss).to be == "2050.17"
        expect(@slaves.first.take_profit).to be == "2077.12"

      end
    end
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do
        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/NETTING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'OPEN', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'334199552', 'deal_ticket':'290610221', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'10001', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 10001'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"NETTING"}
        @account1 = Account.find_by_name("5634787")  
        @account2 = Account.find_by_name("5634788")  
        # @slaves2 = @account1.slaves.where(ticket_master:10001)
        # @slaves2 = @account2.slaves.where(ticket_master:10001)
        expect(@account1.slaves.count).to be == 3
        expect(@account2.slaves.count).to be == 3
        expect(@account1.orders.count).to be == 3
        expect(@account1.slaves.find_by(ticket_master: 10001).state).to be == "executed"
        expect(Account.find_by_name("5634787").slaves.find_by(ticket_master: 10001).state).to be == "executed"
        expect(Account.find_by_name("5634788").slaves.find_by(ticket_master: 10001).state).to be == "pending"
        expect(Account.find_by_name("5634787").slaves.find_by(ticket_master: 10001).lot).to be == "0.200000"
        expect(Account.find_by_name("5634788").slaves.find_by(ticket_master: 10001).lot).to be == "0.2"
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_64/orders/5647753/NETTING',
          params: {"orders"=>"{\"order_id\":10001,\"price\":14940.05000000,\"volume\":0.30000000,\"stop_loss\":15036.41000000,\"take_profit\":14843.06000000,\"type\":1,\"magicnumber\":704,\"symbol\":\"UsaTec\",\"comment\":\"VLL[9CE] N$|S 0.80\",\"open_at\":\"1644424361\",\"state_meta\":modify}"}
        expect(Account.find_by_name("5634787").slaves.find_by(ticket_master: 10001).lot).to be == "0.3"
        expect(Account.find_by_name("5634788").slaves.find_by(ticket_master: 10001).lot).to be == "0.3"
        expect(Account.find_by_name("5634788").transactions.find_by(ticket: 10001).lot).to be == "0.3"
        expect(Account.find_by_name("5634788").transactions.find_by(ticket: 10001).lot).to be == "0.3"

        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/NETTING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'MODIFY_VOLUME', 'order_state':'executed', 'meta_state':'MODIFY_VOLUME', 'ticket_slave_id':'334199552', 'deal_ticket':'290610221', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.300000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'10001', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 10001'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"NETTING"}
        expect(Account.find_by_name("5634787").slaves.find_by(ticket_master: 10001).lot).to be == "0.3"
        expect(Account.find_by_name("5634788").slaves.find_by(ticket_master: 10001).lot).to be == "0.3"
        expect(Account.find_by_name("5634788").transactions.find_by(ticket: 10001).lot).to be == "0.3"
        expect(Account.find_by_name("5634788").transactions.find_by(ticket: 10001).lot).to be == "0.3"


        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING',
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_42", "action"=>"orders", "account_id"=>"3000033103", "account_mode"=>"NETTING"}
        expect(@account1.slaves.find_by(ticket_master: 10001).state).to be == "remove"
        expect(@account2.slaves.find_by(ticket_master: 10001).state).to be == "deleted"

      end
    end
    
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING',
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_42", "action"=>"orders", "account_id"=>"3000033103", "account_mode"=>"NETTING"}
        expect(Account.find_by(name:5634787).slaves.last.state).to be == "deleted"
        # expect(@account1.slaves.last.state).to be == "deleted"
        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/NETTING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'NOSLTP', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'0', 'deal_ticket':'0', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'10001', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 10001'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"NETTING"}

      end
    end

    context 'POST' do
      it 'Hedging - Check Automattically' do
        post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/NETTING',
          params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_42", "action"=>"orders", "account_id"=>"3000033103", "account_mode"=>"NETTING"}
        expect(Account.find_by(name:5634787).slaves.last.state).to be == "deleted"
        # expect(@account1.slaves.last.state).to be == "deleted"
        post '/api/v1/transactions/trasmit/signal_slave/1_53/5634787/NETTING', 
          params: {"body"=> "{'account_login':'5634787', 'magic_number':'704', 'action':'NOSLTP', 'order_state':'pending', 'meta_state':'OPEN', 'ticket_slave_id':'0', 'deal_ticket':'0', 'order_symbol':'UsaTec', 'order_type':'1', 'price_open':'14940.800000', 'price_close':'0.000000', 'volume':'0.200000', 'stop_loss':'15036.41000000', 'take_profit':'14843.06000000', 'profit':'0.000000', 'comment':'10001', 'open_at':'1644424225.000000', 'meta_message':'OrderSend Done | Retcode: 10009 | Deal: 290610221 | Order: 334199552 | Comment: 10001'}", "expert_name"=>"signal_slave", "expert_version"=>"1_53", "account_id"=>"3000033104", "account_mode"=>"NETTING"}

      end
    end
  end
end
#         account = Account.find_by(name: 5634787)
#         @transaction = account.transactions.find_by(ticket: @ticket_master)
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(@account1.state).to be == "enable"
#         expect(@account1.kind).to be == "slave"
#         expect(@transaction.ticket).to be == "10000001" 
#         expect(@slave.ticket_master).to be == "10000001" 
#         expect(@transaction.state).to be == "executed"
#         expect(@slave.state).to be == "pending"
#         @slave.execute
#         expect(@slave.state).to be == "executed"
#         expect(response.status).to eq(201)
#       end

#       it 'Hedging - Verify account 5634788' do
#         account = Account.find_by(name: 5634788)
#         @transaction = account.transactions.find_by(ticket:@ticket_master)
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(@account2.state).to be == "enable"
#         expect(@account2.kind).to be == "slave"

#         expect(@transaction.ticket).to be == "10000001" 
#         expect(@slave.ticket_master).to be == "10000001" 
#         expect(@transaction.state).to be== "executed"
#         expect(@slave.state).to be == "pending"
#         @slave.execute
#         expect(@slave.state).to be == "executed"
#         expect(response.status).to eq(201)
#       end

#       it 'Hedging - Post Remove All Orders' do
#         account = Account.find_by(name: 5634788)
#         @transaction = account.transactions.find_by(ticket:@ticket_master)
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         @slave.execute
#         post '/api/v1/transactions/copy/trasmit/signal_copy/1_3_0/5647753/NETTING', 
#           params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(account.slaves.count).to eq(1)
#         expect(account.slaves.count).not_to eq(2)
#         expect(@transaction.state).to be == "executed"
#         expect(@slave.state).to be == "remove"
#         @slave.close
#         expect(@slave.state).to be == "closed"
#         expect(@slave.master.state).to be == "closed"
#         expect(response.status).to eq(201)

#         # @order = @trace.orders.find_by(message_id: 723517440)
#         # expect(@order.kind).to be == "order"
#       end      

#       it 'Hedging - Remove All Transaction executed should be deleted and not executed should be remove' do
#         account_87 = Account.find_by(name: 5634787)
#         account_88 = Account.find_by(name: 5634788)
#         # @transaction = account_87.transactions.find_by(ticket:@ticket_master)
#         @slave_1 = account_87.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         @slave_1.execute
#         expect(@slave_1.state).to be == "executed"
#         @slave_2 = account_88.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(@slave_2.state).to be == "pending"
#         post '/api/v1/transactions/copy/trasmit/signal_copy/1_3_0/5647753/NETTING', 
#           params: {"orders"=>"", "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
#         @slave_1 = account_87.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         @slave_2 = account_88.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(@slave_1.state).to be == "remove"
#         expect(@slave_2.state).to be == "deleted"
#         expect(@slave_1.master.state).to be == "executed"
#         expect(@slave_2.master.state).to be == "closed"
#         expect(response.status).to eq(201)
#       end

#       it 'Hedging - Remove first transaction and add another transaction' do
#         account = Account.find_by(name: 5634788)
#         @transaction = account.transactions.find_by(ticket:@ticket_master)
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         @slave.execute
#         post '/api/v1/transactions/copy/trasmit/signal_copy/1_3_0/5647753/NETTING', 
#           params: {"orders"=>"{\"order_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
#           "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
#         @slave1 = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(@slave1.state).to be == "remove"
#         @slave2 = account.transactions.find_by(ticket:10000002).slaves.find_by(ticket_master: 10000002)
#         expect(@slave2.state).to be == "pending"
#         # expect(@slave.closed_at).to be_nil
#       end

#       it 'Hedging - Modify Position first transaction and add another order' do
#         account = Account.find_by(name: 5634788)
#         @transaction = account.transactions.find_by(ticket:@ticket_master)
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         @slave.execute
#         post '/api/v1/transactions/copy/trasmit/signal_copy/1_3_0/5647753/NETTING', 
#           params: {"orders"=>"{\"order_id\":10000001,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//{\"order_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}",
#           "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         expect(account.slaves.count).to eq(2)
#         expect(account.slaves.count).not_to eq(1)
#         expect(account.slaves.count).not_to eq(3)
#         expect(@transaction.slaves.count).to eq(1)
#         expect(@transaction.state).to be == "executed"
#         expect(@slave.take_profit).not_to be == "0.0"
#         expect(@slave.stop_loss).not_to be == "0.0"
#         expect(@slave.take_profit).to be == "1.2"
#         expect(@slave.stop_loss).to be == "1.1"
#         @slave.remove
#         expect(@slave.state).to be == "remove"
#         expect(@slave.closed_at).to be_nil
#         @slave.close
#         expect(@slave.closed_at).not_to be_nil
#         expect(@slave.state).to be == "closed"
#         expect(@slave.master.state).to be == "closed"
#         expect(response.status).to eq(201)
#       end

#       it 'Hedging - Modify Position first transaction and add another order' do
#         account = Account.find_by(name: 5634787)
#         @transaction = account.transactions.find_by(ticket:@ticket_master)
#         @slave = account.transactions.find_by(ticket:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
#         @slave.execute
#         post '/api/v1/transactions/copy/trasmit/signal_copy/1_3_0/5647753/NETTING', 
#           params: {"orders"=>"{\"order_id\":10000001,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"modify\"}//{\"order_id\":10000002,\"price\":1.13473000,\"volume\":0.02000000,\"stop_loss\":1.1000000,\"take_profit\":1.2000000,\"type\":0,\"magicnumber\":0,\"symbol\":\"EURUSD\",\"comment\":null,\"open_at\":\"1642789795\",\"state_meta\":\"\"}", 
#           "expert_name"=>"signal_copy", "expert_version"=>"1_30", "account_id"=>"5647753", "account_mode"=>"NETTING"}
#         @slave = Account.find_by(name: 5634787).transactions.find_by(ticket:10000002).slaves.find_by(ticket_master: 10000002)
#         expect(@slave.take_profit).not_to eq(0)
#         expect(@slave.stop_loss).not_to eq(0)
#         expect(@slave.take_profit).to be == ("1.2")
#         expect(@slave.stop_loss).to be == ("1.1")
#         expect(response.status).to eq(201)

#       end

#     end
#   end
# end    
#     # context 'POST /api/v1/orders' do
      

#     #   it 'save a telegram trace message' do
#     #     expect(Order.first.state).to be == "prepared"
#     #     expect(Order.first.symbol).to be == "CADJPY"
#     #     # expect(response).to be_success
#     #     expect(response.status).to eq(201)
#     #     expect(JSON.parse(response.body)).to be == {"id"=>1, "message"=>"BUY 80.39\n\nTP 80.19\nTP 79.89\nTP 79.39\nSL 81.39", "message_id"=>"723517440", "symbol"=>"CADJPY", "trace"=>"RoboSignal"}
#     #   end

#     #   it 'verify lot information' do
#     #     @trace.update(take_profit: 'normal')
#     #     get '/api/v2/orders/723517440'
#     #     expect(JSON.parse(response.body)['lots']).to eq([0.05])

#     #     @trace.update(take_profit: 'Agressive')
#     #     get '/api/v2/orders/723517440'
#     #     expect(JSON.parse(response.body)['lots']).to eq([0.03, 0.02])

#     #     @trace.update(take_profit: 'Superagressive')
#     #     get '/api/v2/orders/723517440'
#     #     expect(JSON.parse(response.body)['lots']).to eq([0.03, 0.02, 0.02])
#     #   end
#     # end


#     # context 'GET /api/v1/orders/723517440' do
#     #   it 'get information of message id' do
#     #     get '/api/v1/orders/723517440'
#     #     expect(JSON.parse(response.body)['id']).to eq(1)
#     #     expect(JSON.parse(response.body)['message_id']).to eq('723517440')
#     #     expect(JSON.parse(response.body)['message'].tr("\n", " ")).to be == 'BUY 80.39  TP 80.19 TP 79.89 TP 79.39 SL 81.39'
#     #     expect(JSON.parse(response.body)['symbol']).to eq('CADJPY')
#     #   end
#     # end

#     # context 'GET /api/v1/orders/' do
#     #   it 'return all sign to execute' do
#     #     get '/api/v1/stores'
#     #     # expect(response).to be_success
#     #     expect(response.status).to eq(200)
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['message_id']).to eq('723517440')
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['type']).to eq('BUY')
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['symbol']).to eq('CADJPY')
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['price_request']).to eq('80.39')
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['SL']).to eq('81.39')
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['TP']).to eq(['80.19', '79.89'])
#     #     expect(JSON.parse(response.body)['traces'][0]['orders'][0]['lots']).to eq([0.03, 0.02])
#     #   end
#     # end
#     # context 'POST /api/v1/orders/transaction' do
#     #   it 'Save transaction from metatrader order' do
        
#     #     post '/api/v1/orders/transaction', params:{
#     #       "chat_id"=>"1",
#     #       "message_id"=>"723517440",
#     #       "provider"=>"1",
#     #       "provider_name"=>"RoboSignal",
#     #       "symbol"=>"CADJPY",
#     #       "action"=>"EXECUTION",
#     #       "kind"=>"0",
#     #       "price_request"=>"80.39",
#     #       "price_open"=>"80.38",
#     #       "stop_loss"=>"81.39",
#     #       "take_profit"=>"80.19",
#     #       "lot"=> "0.03",
#     #       "comment"=>"RoboSignal",
#     #       "magic"=>"123456",
#     #       "ticket"=>"363873673",
#     #       "open_at"=>"2020.10.21 01:18:09",
#     #       "response"=>"10009"
#     #     }

#     #     expect(JSON.parse(response.body)['state']).to eq('executed')
#     #     expect(JSON.parse(response.body)['ticket']).to eq('363873673')
#     #     expect(JSON.parse(response.body)['action']).to eq('EXECUTION')
#     #     expect(JSON.parse(response.body)['kind']).to eq('0')
#     #     expect(JSON.parse(response.body)['symbol']).to eq('CADJPY')
#     #     expect(JSON.parse(response.body)['price_request']).to eq('80.39')
#     #     expect(JSON.parse(response.body)['price_open']).to eq('80.38')
#     #     expect(JSON.parse(response.body)['stop_loss']).to eq('81.39')
#     #     expect(JSON.parse(response.body)['take_profit']).to eq('80.19')
#     #     expect(JSON.parse(response.body)['lot']).to eq('0.03')
#     #     expect(JSON.parse(response.body)['comment']).to eq('RoboSignal')
#     #     expect(JSON.parse(response.body)['magic']).to eq('123456')
#     #     expect(JSON.parse(response.body)['ticket']).to eq('363873673')
#     #     expect(JSON.parse(response.body)['open_at']).to eq('2020-10-21T01:18:09.000Z')
#     #   end

#     #   it 'verify kind order' do
#     #     @order = @trace.orders.find_by(message_id: 723517440)
#     #     @order.execute
#     #     expect(@order.kind).to be == "order"
#     #     expect(@order.state).to be == 'executed'
#     #   end
      
#     # end
#     # context 'POST /api/v1/orders' do
#     #   it 'Error transaction from metatrader order' do
#     #     post '/api/v1/orders/transaction', params:{
#     #       'chat_id': 1, 'message_id': '723517440', 'provider': 1, 'provider_name': 'RoboSignal', 'symbol': 'CADJPY', 'action': 'EXECUTION', 'kind': 1, 'price_request': '80.39', 'price_open': 79.509, 'stop_loss': 'None', 'take_profit': 'None', 'comment': 'RoboSignal #1', 'magic': 123456, 'ticket': 363928013, 'open_at': '2020.10.22 06:36:53', 'response': 'ERROR_SETTING_SL_TP', 'response_value': 'None', 'environment': 'local'
#     #     }
#     #     expect(JSON.parse(response.body)['state']).to eq('error')
#     #   end
#     # end
#     # context '/api/v1/traces' do 
#     #   it 'post close transaction' do
#     #     transaction = create(:transaction, :first, order: @store.traces.first.orders.first)
#     #     transaction.execute
#     #     post '/api/v1/traces/master', params:{
#     #       'message': '5077669|CLOSED|EURNZD|363873673|1|1.182750|1.183030|0.020000|1.198500|1.178500|-0.610000'
#     #     }
#     #     expect(response.body).to eq('true')
#     #     expect(@store.traces.first.orders.first.transactions.first.profit.to_f).to be == -0.61
#     #     expect(@store.traces.first.orders.first.transactions.first.response).to be == "5077669|CLOSED|EURNZD|363873673|1|1.182750|1.183030|0.020000|1.198500|1.178500|-0.610000"
#     #     expect(@store.traces.first.orders.first.transactions.first.state).to be == 'closed'       
#     #     expect(@store.traces.first.orders.first.state).to be == 'closed'       
#     #   end
#     # end

