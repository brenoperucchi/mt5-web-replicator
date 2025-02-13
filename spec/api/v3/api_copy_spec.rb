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
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging',   trace_ids: [1,2], instrument_control:true, account_server: @account_server)
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging',     trace_ids: [1,2], account_server: @account_server,)
    @account_copy2 = create(:account, :copy2, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2], account_server: @account_server)
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging',     trace_ids: [1,2], account_server: @account_server)
    
    # post '/api/v2/copy/post/imentore_copy/2_21/broker_name/10100/HEDGING', 
    #   params: {"imentore_copy"=>"{\"orders_open\":{
    #             \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
    #             \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"-0.07\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
    #           }}"}
  end

  # /api/v2/copy/post/orders/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING
  describe 'POST Copy Orders' do
    let(:file) { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'api', 'v3', 'orders_history.txt')) }
    
    it 'Conciliate Orders - Create New Slave in New Order' do
      post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
        params: { data: file }

      slaves = TransactionSlave.where(ticket_master: 2029093177)
      expect(slaves.count).to be == 4
      expect(slaves.first.state).to be == "pending"

      expect(Order.find_by(content_id: 2029093177).present?).to be true
      expect(Order.find_by(content_id: 2029093177).slaves.count).to be == 2
      expect(Order.find_by(content_id: 2029093177).slaves.first.comment).to be == "2029093177"
      expect(Order.find_by(content_id: 2029093177).slaves.first.ticket_slave).to be == -1
      expect(Order.find_by(content_id: 2029093177).slaves.first.profit).to be == 0
    end

    it 'Verify Transaction State maintain Executed and Order state modify Closed' do
      post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
        params: { data: file }

      transactions = Transaction.where(ticket: 2029093177, trace_id: 1)
      slaves = TransactionSlave.where(ticket_master: 2029093177, trace_id: 1)
      
      expect(transactions.count).to be == 1
      expect(transactions.first.state).to be == "executed"
      expect(transactions.first.orders.first.state).to be == "executed"
      
      expect(slaves.count).to be == 2
      expect(slaves.first.state).to be == "pending"
      
      slave1 = slaves.first
      slave2 = slaves.last
      slave1.execute
      slave2.execute
      expect(slave1.state).to be == "executed"
      expect(slave2.state).to be == "executed"
      
      slave1.close
      slave2.close
      transactions.reload
      
      transaction = Transaction.where(ticket: 2029093177, trace_id: 1).first
      expect(transaction.state).to be == "executed"
      expect(transaction.orders.first.state).to be == "closed"
    end
    
  end

end    