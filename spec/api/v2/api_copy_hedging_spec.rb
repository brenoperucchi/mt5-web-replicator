require 'rails_helper'

RSpec.describe API::V2::APICopy do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @trace = create(:trace, :copy, stores: [@store])
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, store:@store, user:@user_admin)
    @customer = create(:customer, :customer, store:@store, user:@user_customer)
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @ticket_master = 10000001
    
    post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING', 
      params: {"imentore_copy"=>"{\"orders_open\":{
                \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
              }}"}

  end

  describe API::V2::APICopy do 
    context 'Create and Restrict Transaction' do
      it 'Restrict Magic Number' do
        @account_copy.update(magics_accept: "2000 2001")
        expect(@account_copy.magics_accept).to be == "2000 2001"
        open_at = Time.zone.now.to_i.to_s
        open_at = open_at + ".00000000"
        transaction = Transaction.find_by(ticket: 10000001)
        expect(transaction.stop_loss).to be == "0.0"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000021,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}}
                }}"}

        transaction.reload
        expect(transaction.stop_loss).to be == "1.1"
      end
      # TODO - Implementar teste para verificar se o ticket_id é duplicado
      it 'Duplicate Order' do
        open_at = Time.zone.now.to_i.to_s
        open_at = open_at + ".00000000"
        transaction = Transaction.find_by(ticket: 10000001)
        expect(transaction.stop_loss).to be == "0.0"
        post '/api/v2/copy/post/imentore_copy/2_21/MetaQuotes/10100/HEDGING',
            params: {"imentore_copy"=>
                "{
                \"orders_open\":{
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null},
                    \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200579,\"type\":0,\"price_open\":\"0.87401\",\"price_closed\":\"0.87314\",\"volume\":\"0.02\",\"profit\":\"-1.30\",\"fees\":\"-0.0600\",\"stop_loss\":1.10000000,\"take_profit\":1.20000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 16:01:23\",\"close_at\":\"2023.08.02 21:44:28\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":20001,\"state_meta\":\"PROFIT\\/SLTPLOT\",\"comment\":null}}
                }}"}

        transaction.reload
        expect(transaction.stop_loss).to be == "1.1"
      end
    end
  end
end    