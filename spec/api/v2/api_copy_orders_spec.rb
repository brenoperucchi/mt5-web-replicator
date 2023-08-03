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
    
    post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
      params: {"imentore_copy"=>"{\"orders_open\":{
              }}"}
  end

  describe API::V1::APITransactionsCopy do

    context 'Trace - masters_scope'do 
      it 'With out restrict_magic on trace' do
        # @account_copy.trace_ids = 1
        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(@account_copy.name).to be == "10100"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}},
                \"orders_closed\":{
                  \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"1.00\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                }}"}
        orders = Order.all
        expect(orders.count).to be == 4
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 0
        expect(orders.executed.count).to be == 2
        expect(orders.closed.count).to be == 2
        orders = Order.all
        expect(orders.sum(&:profit_copy).to_f).to be == 2.0
        expect(Transaction.closed_info.count).to be == 0
        expect(Trace.first.masters_scope(:masters, :closed).to_a.sum(&:profit).to_f).to be == 1.0
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_closed\":{
                  \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"1.00\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},

                }}"}
        orders = Order.all
        expect(orders.count).to be == 4
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 0
        expect(orders.executed.count).to be == 0
        expect(orders.closed.count).to be == 4
        expect(orders.sum(&:profit_copy).to_f).to be == 4.00
        expect(Trace.first.masters_scope(:masters, :closed).to_a.sum(&:profit).to_f).to be == 2.00
        expect(Transaction.closed_info.count).to be == 0
      end

      it 'Restrict_magic on first trace' do
        # @account_copy.trace_ids = 1
        trace = Trace.first
        trace.magics_accept =  "10001"        
        trace.save

        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(@account_copy.name).to be == "10100"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10002,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}},
                \"orders_closed\":{
                  \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"1.00\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null}
                }}"}
        orders = Order.all
        expect(orders.count).to be == 4
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 1
        expect(orders.executed.count).to be == 1
        expect(orders.closed.count).to be == 2
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_closed\":{
                  \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"1.00\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014193186,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87366\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:40\",\"close_at\":\"2023.08.02 16:08:55\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000004\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000004,\"ticket_deal\":2014193163,\"type\":0,\"price_open\":\"0.87373\",\"price_closed\":\"0.87362\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:06:54\",\"close_at\":\"2023.08.02 16:07:08\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000005\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000005,\"ticket_deal\":2014192721,\"type\":0,\"price_open\":\"1.66990\",\"price_closed\":\"1.66966\",\"volume\":\"0.01\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:40:47\",\"close_at\":\"2023.08.02 15:45:31\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000006\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000006,\"ticket_deal\":2014187057,\"type\":0,\"price_open\":\"1.66908\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:29\",\"close_at\":\"2023.08.02 08:21:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000007\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000007,\"ticket_deal\":2014187055,\"type\":0,\"price_open\":\"1.66874\",\"price_closed\":\"1.66846\",\"volume\":\"0.01\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:20:43\",\"close_at\":\"2023.08.02 08:21:16\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000008\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000008,\"ticket_deal\":2014187040,\"type\":0,\"price_open\":\"1.66907\",\"price_closed\":\"1.66900\",\"volume\":\"0.01\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:37\",\"close_at\":\"2023.08.02 08:18:49\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000009\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000009,\"ticket_deal\":2014187038,\"type\":0,\"price_open\":\"1.66910\",\"price_closed\":\"1.66891\",\"volume\":\"0.01\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:18:35\",\"close_at\":\"2023.08.02 08:18:44\",\"time_gmt\":\"2023.08.02 18:44:37\",\"time_trader\":\"2023.08.02 21:44:37\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000010\":{\"symbol\":\"EURAUD\",\"ticket_id\":10000010,\"ticket_deal\":2014187027,\"type\":0,\"price_open\":\"1.66882\",\"price_closed\":\"1.66858\",\"volume\":\"0.01\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 08:17:35\",\"close_at\":\"2023.08.02 08:17:44\",\"time_gmt\":\"2023.08.02 18:42:52\",\"time_trader\":\"2023.08.02 21:42:52\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000011\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000011,\"ticket_deal\":2014200575,\"type\":0,\"price_open\":\"0.87304\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:33\",\"close_at\":\"2023.08.02 21:44:17\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000012\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000012,\"ticket_deal\":2014200577,\"type\":1,\"price_open\":\"0.87360\",\"price_closed\":\"0.87322\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:07:12\",\"close_at\":\"2023.08.02 21:44:22\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000013\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000013,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000014\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000014,\"ticket_deal\":2014200582,\"type\":0,\"price_open\":\"0.87404\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:59:27\",\"close_at\":\"2023.08.02 21:44:36\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  \"10000015\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000015,\"ticket_deal\":2014200582,\"type\":0,\"price_open\":\"0.87404\",\"price_closed\":\"0.87315\",\"volume\":\"0.02\",\"profit\":\"1.00\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 15:59:27\",\"close_at\":\"2023.08.02 21:44:36\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null}
                }}"}
        orders = Order.all
        expect(orders.count).to be == 4
        expect(orders.pending.count).to be == 0
        expect(orders.error.count).to be == 1
        expect(orders.executed.count).to be == 0
        expect(orders.closed.count).to be == 3
        expect(orders.sum(&:profit_copy).to_f).to be == 4
        expect(Transaction.closed_info.count).to be == 0
        expect(Trace.first.masters_scope(:masters, :closed).to_a.sum(&:profit).to_f).to be == 1.00

        trace.save
        expect(orders.sum(&:profit_copy).to_f).to be == 4.00
        expect(trace.masters_scope(:masters, :closed).to_a.sum(&:profit).to_f).to be == 1.00
        expect(Transaction.closed_info.count).to be == 0
      end
    end

    context 'Traces - Close Orders' do
      it 'Traces with two accounts copys' do
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  }}"}
        expect(Account.find_by_name(10100).traces.first.masters.count).to be == 2
        expect(Account.find_by_name(10100).traces.last.masters.count).to be == 2

        expect(TransactionSlave.where(ticket_master: 10000001, account: @account1).count).to be == 1
        expect(TransactionSlave.where(ticket_master: 10000001, account: @account2).count).to be == 1
        expect(TransactionSlave.where(ticket_master: 10000001, account: @account3).count).to be == 0
        expect(TransactionSlave.where(ticket_master: 10000002, account: @account1).count).to be == 1
        expect(TransactionSlave.where(ticket_master: 10000002, account: @account2).count).to be == 1
        expect(TransactionSlave.where(ticket_master: 10000002, account: @account3).count).to be == 0

        expect(Account.find_by_name(10100).traces.first.transactions.count).to be == 2
        expect(Account.find_by_name(10100).traces.first.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(10100).traces.first.transactions.where(state:'executed').count).to be == 2
        expect(Account.find_by_name(10100).traces.last.transactions.where(state:'executed').count).to be == 2
        

        expect(Order.where(content_id: 10000001).first.id).to be                                            == 9
        expect(Order.where(content_id: 10000001).first.slaves.where(state:'pending').count).to be           == 2
        expect(Order.where(content_id: 10000001).first.slaves.count).to be                                  == 2

        expect(Order.where(content_id: 10000001).last.id).to be                                            == 10
        expect(Order.where(content_id: 10000001).last.slaves.where(state:'pending').count).to be           == 1
        expect(Order.where(content_id: 10000001).last.slaves.count).to be                                  == 1
        
        expect(Account.find_by_name(10200).traces.first.transactions.where(state:'executed').count).to be    == 2
        expect(Account.find_by_name(10200).traces.first.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'executed').count).to be     == 2
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'closed_info').count).to be  == 0

        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},

                  }}"}
        expect(Account.find_by_name(10100).traces.first.transactions.count).to be == 3
        expect(Account.find_by_name(10100).traces.first.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(10100).traces.first.transactions.where(state:'executed').count).to be == 3
        expect(Account.find_by_name(10100).traces.last.transactions.where(state:'executed').count).to be == 3
        
        expect(Account.find_by_name(10200).traces.first.transactions.where(state:'executed').count).to be == 3
        expect(Account.find_by_name(10200).traces.first.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'executed').count).to be == 3
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'closed_info').count).to be == 0

        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_closed\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                    \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  }}"}
        expect(Account.find_by_name(10100).traces.first.transactions.count).to be == 3
        expect(Account.find_by_name(10100).traces.first.transactions.where(state:'executed').count).to be == 0
        expect(Account.find_by_name(10100).traces.first.transactions.where(state:'closed').count).to be == 3
        expect(Account.find_by_name(10100).traces.last.transactions.where(state:'executed').count).to be == 0
        
        expect(Account.find_by_name(10200).traces.first.transactions.where(state:'executed').count).to be == 0
        expect(Account.find_by_name(10200).traces.first.transactions.where(state:'closed').count).to be == 3
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'executed').count).to be == 0
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'closed_info').count).to be == 0
        expect(Account.find_by_name(10200).traces.last.transactions.where(state:'closed').count).to be == 3

      end
    end
    context 'Control Instrument' do# focus:true do
      it 'Hedging - Change instruments on copy to slaves' do
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                    \"10000003\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000003,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                    \"10000004\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000004,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"0\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"comment\":null},
                  }}"}
        account = Account.find_by_name(20200)
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
        expect(@account_copy.name).to be == "10100"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000001\":{\"symbol\":\"GBPUSD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  }}"}        
        order = Order.find_by(content_id: 10000001)          
        expect(order.trace.instrument_control).to be == true
        expect(order.content_id).to be == 10000001
        expect(order.state).to be == "executed"
        expect(order.symbol).not_to be == "GBPCAD"
        @account_copy.instruments.create(symbol: 'GBPUSD', name: 'GBPCAD', volumes:0.01)
        expect(order.transactions.first.symbol).to be == "GBPUSD"
        expect(order.slaves.first.symbol).to be == "GBPCAD"
        expect(order.slaves.first.symbol).not_to be == "GBPUSD"
        
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000002\":{\"symbol\":\"GBPUSD\",\"ticket_id\":10000002,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  }}"}        
        order = Order.find_by(content_id: 10000002)          
        expect(order.content_id).to be == 10000002
        expect(order.state).to be == "executed"
        expect(order.symbol).to be == "GBPUSD"
        expect(order.transactions.first.symbol).to be == "GBPUSD"
        expect(order.slaves.first.symbol).to be == "GBPCAD"
        expect(order.slaves.first.symbol).not_to be == "GBPUSD"
      end
      it 'Trace - Create order all traces'do 
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000003\":{\"symbol\":\"GBPUSD\",\"ticket_id\":10000003,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  }}"}                
        orders = Order.where(content_id: 10000003)
        expect(orders.count).to be == 2
        order = orders.last
        expect(order.trace.instrument_control).to be == nil
        expect(order.account.name).to be == "10100"
        expect(order.account.instrument_control).to be == true
        expect(order.trace.name).to be == "SignalCopy2"
        expect(order.transactions.first.symbol).to be == "GBPUSD"
        expect(order.slaves.first.symbol).to be == "GBPUSD"
      end
      
      it 'Trace - One trace disable'do 
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000004\":{\"symbol\":\"GBPUSD\",\"ticket_id\":10000004,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  }}"}          
        slaves = TransactionSlave.where(ticket_master: 10000004)
        expect(slaves.count).to be == 3
        expect(slaves[0].trace).to be == @trace
        expect(slaves[1].trace).to be == @trace
        expect(slaves[2].trace).to be == @trace2
        
        @trace2.soft_destroy
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000005\":{\"symbol\":\"GBPUSD\",\"ticket_id\":10000005,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  }}"}                
        slaves = TransactionSlave.where(ticket_master: 10000005)
        expect(slaves.count).to be == 2
        expect(slaves[0].trace).to be == @trace
        expect(slaves[1].trace).to be == @trace
        expect(TransactionSlave.where(ticket_master: 10000005, trace:@trace2)).to be_empty
      end
    end
  end
  describe API::V1::APITransactionsCopy do
    context 'POST' do
      it 'Hedging - Restrict Magic Number' do
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
          params: {"imentore_copy"=>"{\"orders_open\":{
                    \"10000005\":{\"symbol\":\"GBPUSD\",\"ticket_id\":10000005,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000, \"profit\":\"0\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":10001,\"state_meta\":null,\"comment\":null},
                  }}"}            
        Current.user = @user
        account = Account.find_by(name: 20100)
        expect(account.orders.where(content_id:10000005).count).to be == 1

        Account.find_by(name: 10100).update(magics_accept: 20000)
        account = Account.find_by(name: 10100)
        order = account.orders.find_by(content_id:10000005)
        transaction = order.transactions.first
        expect(Order.all.count).to be == 2
        expect(order.state).to be == "executed"
        expect(order.transactions.count).to be == 1
        expect(transaction.state).to be == "executed"
        expect(order.slaves.count).to be == 2
        slave1 = order.slaves.first
        slave2 = order.slaves.last
        expect(slave1.id).to be == 46
        expect(slave2.id).to be == 47
        expect(slave1.state).to be == "pending"
        expect(slave2.state).to be == "pending"
        transaction.close
        expect(transaction.state).to be == "closed"
        expect(order.state).to be == "closed"

      end
 
      it 'Hedging - Restrict Magic Number' do
        account = Account.find_by(name: 20100)
        # @transaction = account.orders.find_by(content_id:10000005).transactions.first
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