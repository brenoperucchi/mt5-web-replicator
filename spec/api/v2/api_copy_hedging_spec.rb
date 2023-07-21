require 'rails_helper'

RSpec.describe API::V2::APICopy do
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
    @ticket_master = 10000001
    
    post '/api/v2/copy/post/imentore_copy/2_20/ActivTradesCorpServer/5647753/HEDGING', 
      params:  {"imentore_copy"=>"{\"orders_open\":{\"10001\":{\"symbol\":\"EURAUD\",\"ticket_id\":10001,\"ticket_deal\":20001,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64838000,\"price_closed\":1.64810000,\"profit\":-0.38000000,\"fees\":-0.12000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 07:01:26\",\"close_at\":\"2023.07.18 07:01:58\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"magic_number\":0,\"comment\":null},\"10002\":{\"symbol\":\"EURAUD\",\"ticket_id\":10002,\"ticket_deal\":20002,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64840000,\"price_closed\":1.64825000,\"profit\":-0.20000000,\"fees\":-0.12000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 06:59:48\",\"close_at\":\"2023.07.18 06:59:53\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"magic_number\":0,\"comment\":null},\"10003\":{\"symbol\":\"EURAUD\",\"ticket_id\":10003,\"ticket_deal\":20003,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64836000,\"price_closed\":1.64825000,\"profit\":-0.15000000,\"fees\":-0.12000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 06:59:40\",\"close_at\":\"2023.07.18 06:59:53\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"magic_number\":0,\"comment\":null},\"10004\":{\"symbol\":\"EURAUD\",\"ticket_id\":10004,\"ticket_deal\":20003,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64836000,\"price_closed\":1.64825000,\"profit\":-0.15000000,\"fees\":-0.12000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 06:59:37\",\"close_at\":\"2023.07.18 06:59:53\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"magic_number\":0,\"comment\":null}}}"}
  end

  describe API::V2::APICopy do 
    context 'Create and Restrict Transaction' do
      it 'Restrict Magic Number', focus:true do
        @account_copy.update(magics_accept: "2000 2001")
        expect(@account_copy.magics_accept).to be == "2000 2001"
        open_at = Time.zone.now.to_i.to_s
        open_at = open_at + ".00000000"
        transaction = Transaction.find_by(ticket: 10001)
        expect(transaction.stop_loss).to be == "0.0"
        post '/api/v2/copy/post/imentore_copy/2_20/ActivTradesCorpServer/5647753/HEDGING', 
        params: {"imentore_copy"=>"{\"orders_open\":{
                  \"10001\":{\"symbol\":\"EURAUD\",\"ticket_id\":10001,\"ticket_deal\":20001,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64838000,\"price_closed\":1.64810000,\"profit\":-0.38000000,\"fees\":-0.12000000,\"stop_loss\":1.5,\"take_profit\":1.6,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 07:01:26\",\"close_at\":\"2023.07.18 07:01:58\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"state_meta\":\"PROFIT/SLTPLOT\",\"magic_number\":0,\"comment\":null},
                  \"10002\":{\"symbol\":\"EURAUD\",\"ticket_id\":10002,\"ticket_deal\":20002,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64840000,\"price_closed\":1.64825000,\"profit\":-0.20000000,\"fees\":-0.12000000,\"stop_loss\":1.5,\"take_profit\":1.6,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 06:59:48\",\"close_at\":\"2023.07.18 06:59:53\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"state_meta\":\"PROFIT/SLTPLOT\",\"magic_number\":0,\"comment\":null},
                  \"10003\":{\"symbol\":\"EURAUD\",\"ticket_id\":10003,\"ticket_deal\":20003,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64836000,\"price_closed\":1.64825000,\"profit\":-0.15000000,\"fees\":-0.12000000,\"stop_loss\":1.5,\"take_profit\":1.6,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 06:59:40\",\"close_at\":\"2023.07.18 06:59:53\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"state_meta\":\"PROFIT/SLTPLOT\",\"magic_number\":0,\"comment\":null},
                  \"10004\":{\"symbol\":\"EURAUD\",\"ticket_id\":10004,\"ticket_deal\":20003,\"type\":0,\"volume\":0.02000000,\"price_open\":1.64836000,\"price_closed\":1.64825000,\"profit\":-0.15000000,\"fees\":-0.12000000,\"stop_loss\":1.5,\"take_profit\":1.6,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.07.18 06:59:37\",\"close_at\":\"2023.07.18 06:59:53\",\"time_gmt\":\"2023.07.19 18:02:56\",\"time_trader\":\"2023.07.19 21:02:56\",\"timezone\":-6,\"state_meta\":\"PROFIT/SLTPLOT\",\"magic_number\":0,\"comment\":null},
                }}"}
        transaction.reload
        expect(transaction.stop_loss).to be == "1.5"
        binding.pry
      end
    end
  end
end    