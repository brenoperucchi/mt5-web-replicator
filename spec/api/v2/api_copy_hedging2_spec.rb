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
    
    post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
      params: {"imentore_copy"=>"{\"orders_open\":{
                \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
                \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"-0.07\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014193186,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87366\",\"volume\":\"0.02\",\"profit\":\"-0.11\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:40\",\"close_at\":\"2023.08.02 16:08:55\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000004\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000004,\"ticket_deal\":2014193163,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87362\",\"volume\":\"0.02\",\"profit\":\"-0.17\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:06:54\",\"close_at\":\"2023.08.02 16:07:08\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000005\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000005,\"ticket_deal\":2014192721,\"type\":0,\"price_open\":\"1.66990\",\"price_closed\":\"1.66966\",\"volume\":\"0.01\",\"profit\":\"-0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:40:47\",\"close_at\":\"2023.08.02 15:45:31\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000006\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000006,\"ticket_deal\":2014187057,\"type\":0,\"price_open\":\"1.66908\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"-0.41\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:29\",\"close_at\":\"2023.08.02 08:21:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000007\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000007,\"ticket_deal\":2014187055,\"type\":0,\"price_open\":\"1.66874\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"-0.18\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:20:43\",\"close_at\":\"2023.08.02 08:21:16\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000008\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000008,\"ticket_deal\":2014187040,\"type\":0,\"price_open\":\"1.66907\",\"price_closed\":\"1.66900\",\"volume\":\"0.01\",\"profit\":\"-0.05\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:37\",\"close_at\":\"2023.08.02 08:18:49\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000009\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000009,\"ticket_deal\":2014187038,\"type\":0,\"price_open\":\"1.66910\",\"price_closed\":\"1.66891\",\"volume\":\"0.01\",\"profit\":\"-0.13\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:35\",\"close_at\":\"2023.08.02 08:18:44\",\"time_gmt\":\"2023.08.02 18:44:37\",\"time_trader\":\"2023.08.02 21:44:37\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000010\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000010,\"ticket_deal\":2014187027,\"type\":0,\"price_open\":\"1.66882\",\"price_closed\":\"1.66858\",\"volume\":\"0.01\",\"profit\":\"-0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:17:35\",\"close_at\":\"2023.08.02 08:17:44\",\"time_gmt\":\"2023.08.02 18:42:52\",\"time_trader\":\"2023.08.02 21:42:52\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000011\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000011,\"ticket_deal\":2014200575,\"type\":0,\"price_open\":\"0.87304\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:33\",\"close_at\":\"2023.08.02 21:44:17\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000012\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000012,\"ticket_deal\":2014200577,\"type\":1,\"price_open\":\"0.87360\",\"price_closed\":\"0.87322\",\"volume\":\"0.02\",\"profit\":\"0.57\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:12\",\"close_at\":\"2023.08.02 21:44:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000013\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000013,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                \"10000014\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000014,\"ticket_deal\":2014200582,\"type\":0,\"price_open\":\"0.87404\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"-1.33\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:59:27\",\"close_at\":\"2023.08.02 21:44:36\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null}
              }}"}
      
  end

  describe API::V1::APITransactionsCopy do
    context 'Create and Restrict Transaction' do
      it 'Restrict Magic Number' do 
        @account_copy.update(magics_accept: "2000 2001")
        expect(@account_copy.magics_accept).to be == "2000 2001"
        open_at = Time.zone.now.to_i.to_s
        open_at = open_at + ".00000000"
        expect(Order.all.count).to be == 14

        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
        params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000015\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000015,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                    \"10000016\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000016,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null}},
                \"orders_closed\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null}}}"}
        
        expect(Order.all.count).to be == 16
        expect(Order.error.count).to be == 2
        expect(Order.executed.count).to be == 13
        expect(Order.closed.count).to be == 1
        
        expect(Transaction.all.count).to be == 16
        expect(Transaction.error.count).to be == 2
        expect(Transaction.executed.count).to be == 13
        expect(Transaction.closed.count).to be == 1
        expect(Transaction.closed_info.count).to be == 0

        expect(TransactionSlave.all.count).to be == 28
        expect(TransactionSlave.error.count).to be == 0
        expect(TransactionSlave.executed.count).to be == 0
        expect(TransactionSlave.closed.count).to be == 0
        expect(TransactionSlave.pending.count).to be == 26
        expect(TransactionSlave.remove.count).to be == 0
        expect(TransactionSlave.deleted.count).to be == 2

        order = Order.where(content_id:10000015).take
        expect(order.content_id).to be == 10000015
        expect(order.transactions.find_by(account:@account_copy).ticket).to be == 10000015
        expect(order.transactions.find_by(account:@account_copy).state).to be == "error"
        expect(order.transactions.count).to be == 1
        expect(order.slaves.count).to be == 0
        expect(order.state).to be == "error"
      end
    end
    
    context 'POST' do
      it 'Hedging - Contract Max Set 3 - order volume decimal' do
        account = Account.find_by(name: 20100)
        order = account.orders.find_by(content_id:10000001)
        expect(account.contract_volume).to be == "1"
        expect(order.slaves.first.lot).to be == "0.01"
        expect(order.transactions.first.lot).to be == "0.02"
        account.update(contract_volume: "3")
        account.reload
        expect(account.contract_volume).to be == "3"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        order = Order.find_by(content_id:10000017)
        expect(order.slaves.first.lot).to be == "0.03"
      end

      it 'Hedging - Contract Max Set 3 - order volume decimal and higher then contract_volume' do
        account = Account.find_by(name: 20100)
        order = account.orders.find_by(content_id:10000001)
        expect(account.contract_volume).to be == "1"
        account.update(contract_volume: "3")
        account.reload
        expect(account.contract_volume).to be == "3"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.04\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        order = Order.find_by(content_id:10000017)
        expect(order.slaves.first.lot).to be == "0.03"
      end

      it 'Hedging - Contract Max Set 3 - order volume integer' do
        account = Account.find_by(name: 20100)
        account.update(contract_volume: "0")
        account.reload
        expect(account.contract_volume).to be == "0"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.0005\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        order = Order.find_by(content_id:10000017)
        expect(order.slaves.first.lot).to be == "0.0005"
      end
    end

    context 'POST' do
      it 'Hedging - Contract Max Set 3 - order volume integer' do
        account = Account.find_by(name: 20100)
        account.update(contract_volume: "3")
        account.reload
        expect(account.contract_volume).to be == "3"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"1\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        order = Order.find_by(content_id:10000017)
        expect(order.slaves.first.lot).to be == "3"
      end

      it 'Hedging - Contract Max Set nil or 0 - slave lot must be copy lot' do
        account = Account.find_by(name: 20100)
        account.update(contract_volume: "0")
        account.reload
        expect(account.contract_volume).to be == "0"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"1\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        order = Order.find_by(content_id:10000017)
        expect(order.slaves.first.lot).to be == "1"        

        account.update(contract_volume: "")
        account.reload
        expect(account.contract_volume).to be == ""
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000018\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000018,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.01\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        order = Order.find_by(content_id:10000018)
        expect(order.slaves.first.lot).to be == "0.01"
      end
    end

    context 'POST' do
      it 'Hedging - Should Restrict Order by Magic Number On Copy Account' do
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 10100).update(magics_accept: "20000")
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}
        account = Account.find_by(name: 10100)
        order = account.orders.find_by(content_id:10000017)
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
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 10100).update(magics_accept: "20000")
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000017\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000017,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20000,\"comment\":null}
                  }}"}        
        account = Account.find_by(name: 10100)
        order = account.orders.find_by(content_id:10000017)
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
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Trace.find(1).update(magics_accept: "20001")
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000018\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000018,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20000,\"comment\":null}
                  }}"}           
        account = Account.find_by(name: 10100)
        order = account.orders.find_by(content_id:10000018)
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
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Trace.find(1).update(magics_accept: "20001")
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000019\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000019,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20000,\"comment\":null}
                  }}"}  
        account = Account.find_by(name: 10100)
        order = account.orders.find_by(content_id:10000019)
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
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@transaction.loggings.count).to be == 1
        expect(@transaction.state).to be == "executed"
        expect(@transaction.order.state).to be == "executed"

        Account.find_by(name: 10100).update(magics_accept: "20000")
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{\"orders_open\":{
                    \"10000019\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000019,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}
                  }}"}  
        account = Account.find_by(name: 10100)
        order = account.orders.find_by(content_id:10000019)
        @transaction = order.transactions.first
        expect(@transaction.loggings.count).to be == 2
        expect(@transaction.state).to be == "error"
        expect(@transaction.order.state).to be == "error"
        expect(order.state).to be == "error"
        expect(order.slaves.count).to be == 0
      end

      it 'Hedging - Verify account 20100' do
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        # @slave = account.orders.find_by(content_id:@ticket_master).slaves.find_by(ticket_master: @ticket_master)
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(account.orders.where(content_id:10000001).count).to eq(1)
        expect(@account1.state).to be == "enable"
        expect(@account1.kind).to be == "slave"
        expect(@transaction.ticket).to be == 10000001
        expect(@slave.ticket_master).to be == 10000001
        expect(@transaction.state).to be == "executed"
        expect(@slave.state).to be == "pending"
        expect(@slave.seconds_ago).to be <= 30
        expect(@slave.seconds_ago).to be >= 0

        @slave.execute
        expect(@slave.state).to be == "executed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Verify account 20200' do
        account = Account.find_by(name: 20200)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        expect(@account2.state).to be == "enable"
        expect(@account2.kind).to be == "slave"

        expect(@transaction.ticket).to be == 10000001
        expect(@slave.ticket_master).to be == 10000001
        expect(@transaction.state).to be== "executed"
        expect(@slave.state).to be == "pending"
        @slave.execute
        expect(@slave.state).to be == "executed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Post Remove 14 Orders and create a new' do
        account = Account.find_by(name: 20200)
        # @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        # @slave = account.slaves.find_by(ticket_master: @ticket_master)
        # @slave.execute
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000020\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000020,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}},
                \"orders_closed\":{
                  \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
                  \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"-0.07\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014193186,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87366\",\"volume\":\"0.02\",\"profit\":\"-0.11\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:40\",\"close_at\":\"2023.08.02 16:08:55\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000004\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000004,\"ticket_deal\":2014193163,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87362\",\"volume\":\"0.02\",\"profit\":\"-0.17\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:06:54\",\"close_at\":\"2023.08.02 16:07:08\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000005\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000005,\"ticket_deal\":2014192721,\"type\":0,\"price_open\":\"1.66990\",\"price_closed\":\"1.66966\",\"volume\":\"0.01\",\"profit\":\"-0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:40:47\",\"close_at\":\"2023.08.02 15:45:31\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000006\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000006,\"ticket_deal\":2014187057,\"type\":0,\"price_open\":\"1.66908\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"-0.41\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:29\",\"close_at\":\"2023.08.02 08:21:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000007\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000007,\"ticket_deal\":2014187055,\"type\":0,\"price_open\":\"1.66874\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"-0.18\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:20:43\",\"close_at\":\"2023.08.02 08:21:16\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000008\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000008,\"ticket_deal\":2014187040,\"type\":0,\"price_open\":\"1.66907\",\"price_closed\":\"1.66900\",\"volume\":\"0.01\",\"profit\":\"-0.05\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:37\",\"close_at\":\"2023.08.02 08:18:49\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000009\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000009,\"ticket_deal\":2014187038,\"type\":0,\"price_open\":\"1.66910\",\"price_closed\":\"1.66891\",\"volume\":\"0.01\",\"profit\":\"-0.13\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:35\",\"close_at\":\"2023.08.02 08:18:44\",\"time_gmt\":\"2023.08.02 18:44:37\",\"time_trader\":\"2023.08.02 21:44:37\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000010\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000010,\"ticket_deal\":2014187027,\"type\":0,\"price_open\":\"1.66882\",\"price_closed\":\"1.66858\",\"volume\":\"0.01\",\"profit\":\"-0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:17:35\",\"close_at\":\"2023.08.02 08:17:44\",\"time_gmt\":\"2023.08.02 18:42:52\",\"time_trader\":\"2023.08.02 21:42:52\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000011\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000011,\"ticket_deal\":2014200575,\"type\":0,\"price_open\":\"0.87304\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:33\",\"close_at\":\"2023.08.02 21:44:17\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000012\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000012,\"ticket_deal\":2014200577,\"type\":1,\"price_open\":\"0.87360\",\"price_closed\":\"0.87322\",\"volume\":\"0.02\",\"profit\":\"0.57\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:12\",\"close_at\":\"2023.08.02 21:44:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000013\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000013,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000014\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000014,\"ticket_deal\":2014200582,\"type\":0,\"price_open\":\"0.87404\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"-1.33\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:59:27\",\"close_at\":\"2023.08.02 21:44:36\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null}}
                }"}

        slave = account.slaves.find_by(ticket_master: 10000020)
        slave.execute
        expect(account.slaves.executed.count).to be == 1
        expect(account.slaves.count).not_to be == 2
        expect(slave.master.state).to be == "executed"
        expect(slave.state).to be == "executed"
        slave.remove
        expect(slave.state).to be == "remove"
        expect(slave.master.state).to be == "executed"
        slave.close
        expect(slave.state).to be == "closed"
        expect(slave.master.state).to be == "executed"
        slave.master.close
        expect(slave.master.state).to be == "closed"
        expect(response.status).to be == 201
      end      

      it 'Hedging - Remove All Transaction executed should be deleted and not executed should be remove' do
        account_87 = Account.find_by(name: 20100)
        account_88 = Account.find_by(name: 20200)
        # @transaction = account_87.transactions.find_by(ticket:@ticket_master)
        @slave_1 = account_87.slaves.find_by(ticket_master: @ticket_master)
        @slave_1.execute
        expect(@slave_1.state).to be == "executed"
        @slave_2 = account_88.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave_2.state).to be == "pending"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_closed\":{
                  \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
                  \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"-0.07\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014193186,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87366\",\"volume\":\"0.02\",\"profit\":\"-0.11\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:40\",\"close_at\":\"2023.08.02 16:08:55\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000004\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000004,\"ticket_deal\":2014193163,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87362\",\"volume\":\"0.02\",\"profit\":\"-0.17\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:06:54\",\"close_at\":\"2023.08.02 16:07:08\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000005\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000005,\"ticket_deal\":2014192721,\"type\":0,\"price_open\":\"1.66990\",\"price_closed\":\"1.66966\",\"volume\":\"0.01\",\"profit\":\"-0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:40:47\",\"close_at\":\"2023.08.02 15:45:31\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000006\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000006,\"ticket_deal\":2014187057,\"type\":0,\"price_open\":\"1.66908\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"-0.41\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:29\",\"close_at\":\"2023.08.02 08:21:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000007\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000007,\"ticket_deal\":2014187055,\"type\":0,\"price_open\":\"1.66874\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"-0.18\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:20:43\",\"close_at\":\"2023.08.02 08:21:16\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000008\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000008,\"ticket_deal\":2014187040,\"type\":0,\"price_open\":\"1.66907\",\"price_closed\":\"1.66900\",\"volume\":\"0.01\",\"profit\":\"-0.05\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:37\",\"close_at\":\"2023.08.02 08:18:49\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000009\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000009,\"ticket_deal\":2014187038,\"type\":0,\"price_open\":\"1.66910\",\"price_closed\":\"1.66891\",\"volume\":\"0.01\",\"profit\":\"-0.13\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:35\",\"close_at\":\"2023.08.02 08:18:44\",\"time_gmt\":\"2023.08.02 18:44:37\",\"time_trader\":\"2023.08.02 21:44:37\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000010\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000010,\"ticket_deal\":2014187027,\"type\":0,\"price_open\":\"1.66882\",\"price_closed\":\"1.66858\",\"volume\":\"0.01\",\"profit\":\"-0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:17:35\",\"close_at\":\"2023.08.02 08:17:44\",\"time_gmt\":\"2023.08.02 18:42:52\",\"time_trader\":\"2023.08.02 21:42:52\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000011\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000011,\"ticket_deal\":2014200575,\"type\":0,\"price_open\":\"0.87304\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"0.16\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:33\",\"close_at\":\"2023.08.02 21:44:17\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000012\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000012,\"ticket_deal\":2014200577,\"type\":1,\"price_open\":\"0.87360\",\"price_closed\":\"0.87322\",\"volume\":\"0.02\",\"profit\":\"0.57\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:12\",\"close_at\":\"2023.08.02 21:44:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000013\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000013,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
                  \"10000014\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000014,\"ticket_deal\":2014200582,\"type\":0,\"price_open\":\"0.87404\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"-1.33\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:59:27\",\"close_at\":\"2023.08.02 21:44:36\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null}}
                }"}
        @slave_1 = account_87.slaves.find_by(ticket_master: @ticket_master)
        @slave_2 = account_88.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave_1.state).to be == "remove"
        expect(@slave_2.state).to be == "deleted"
        expect(@slave_1.master.state).to be == "closed"
        expect(@slave_2.master.state).to be == "closed"
        expect(response.status).to be == 201
      end

      it 'Hedging - Remove first transaction and add another transaction' do 
        account = Account.find_by(name: 20200)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000020\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000020,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"comment\":null}},
                \"orders_closed\":{
                  \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null}}
                }"}

        @slave1 = account.slaves.find_by(ticket_master: @ticket_master)
        expect(@slave1.state).to be == "remove"
        @slave2 = account.slaves.find_by(ticket_master: 10000020)
        expect(@slave2.state).to be == "pending"
        # expect(@slave.closed_at).to be_nil
      end
    end

    context 'POST' do
      it 'Hedging - Modify Position first transaction and add another order' do
        account = Account.find_by(name: 20200)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000021\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000021,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}},
                \"orders_closed\":{
                  \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
                }}"}
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.reload
        expect(@slave.state).to be == "executed"
        expect(@slave.order.state).to be == "executed"
        expect(@transaction.state).to be == "executed"

        expect(account.slaves.count).to be == 15
        # expect(account.slaves.count).not_to be == 1
        # expect(account.slaves.count).not_to be == 3
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
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}},
                \"orders_closed\":{}
                }}"}
        @account = Account.find_by(name: 20100)
        @transaction = @account.orders.find_by(content_id:10000002).transactions.first
        @slave = @transaction.slaves.find_by(ticket_master: 10000002)
        expect(@account.orders.count).to be == 14
        expect(@slave.order.content_id).to be == 10000002
        expect(@slave.order.id).to be == 2
        expect(@slave.take_profit).not_to be == 0
        expect(@slave.stop_loss).not_to be == 0
        expect(@slave.take_profit).to be == "1.2"
        expect(@slave.stop_loss).to be == "1.1"
        expect(response.status).to be == 201
      end

      it 'Hedging - Close Order' do
        account = Account.find_by(name: 20100)
        @transaction = account.orders.find_by(content_id:@ticket_master).transactions.first
        @slave = account.slaves.find_by(ticket_master: @ticket_master)
        @slave.execute
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_closed\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}
                }}"}
        @account = Account.find_by(name: 20100)
        @order1 = @account.orders.find_by(content_id:10000001)
        @transaction = @order1.transactions.find_by(ticket: 10000001)
        @slave = @order1.slaves.find_by(ticket_master: 10000001, account: account)
        @account2 = Account.find_by(name: 20200)
        @order2 = @account2.orders.find_by(content_id: 10000001)
        @transaction2 = @account2.transactions.find_by(ticket:10000001)
        @slave2 = @order2.slaves.find_by(ticket_master: 10000001, account: @account2)

        expect(@slave.ticket_master).to be == 10000001
        expect(@transaction.ticket).to be == 10000001
        expect(@slave.state).to be == "remove"
        expect(@slave.master.state).to be == "closed"
        expect(@order1.id).to be == 1
        expect(@order1.state).to be == "closed"


        expect(@slave2.ticket_master).to be == 10000001
        expect(@transaction2.ticket).to be == 10000001
        expect(@slave2.state).to be == "deleted"
        expect(@slave2.master.state).to be == "closed"
        expect(@order2.id).to be == 1
        expect(@order2.state).to be == "closed"
        expect(response.status).to be == 201
      end
    end
  end
end    