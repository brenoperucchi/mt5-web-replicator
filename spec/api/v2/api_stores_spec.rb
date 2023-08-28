require 'rails_helper'

RSpec.describe API::V2::APIStore do
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
    
    # @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    # @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    # @account4 = create(:account, :slave4, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    # @account_copy2 = create(:account, :copy2, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2])
    
    # post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/10100/HEDGING', 
    # params: {"orders"=>"
    #   {\"ticket_id\":483852116,\"open_price\":0.87114000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":1,\"magicnumber\":57392193,\"symbol\":\"EURGBP\",\"comment\":\"57392193\",\"open_at\":1668124835,\"timezone\":-4,\"state_meta\":null}//
    #   {\"ticket_id\":483854383,\"open_price\":1.16938000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395585,\"symbol\":\"GBPUSD\",\"comment\":\"57395585\",\"open_at\":1668130203,\"timezone\":-4,\"state_meta\":null}//
    #   {\"ticket_id\":483854633,\"open_price\":1.16734000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395828,\"symbol\":\"GBPUSD\",\"comment\":\"57395828\",\"open_at\":1668130644,\"timezone\":-4,\"state_meta\":null}//
    #   {\"ticket_id\":483857785,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", 
    #     "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"10100", "account_mode"=>"HEDGING"}
  end

  describe API::V2::APIStore do
    context 'APIStoreStore Config' do
      it 'Create AccountServer Name same STORE with different customer' do 
        post "/api/v2/stores/config/imentore_copy/2_10/DarwinexDemo/10100/HEDGING", params: {'EnvironmentLocal':'1'}
        # post "/api/v2/stores/config/imentore_copy/2_10/XPDEMO/10100/HEDGING", params: {'EnvironmentLocal':'1'}
        expect(AccountServer.all.size).to be == 1
        expect(Account.find_by(name: 10100, account_server_id:1).id).to be == 1
        expect(Account.find_by(name: 10100, account_server_id:1).account_server.name).to be == "darwinexdemo"
        expect(Account.find_by(name: 10100, account_server_id:1).account_server_id).to be == 1
        # expect(Account.find_by(name: 10100, account_server_id:2).account_server.name).to be == "darwinexdemo"
        # account = Account.find_by(name_id: params[:account_name_id])

        # @store2 = create(:store, :store2, plan_id: @plan1.id)
        @customer2 = create(:customer, :customer2, store:@store, user:@user_customer)
        @account_copy2 = create(:account, :copy, store: @store, customer:@customer2, meta_margin_mode: 'hedging', trace_ids: [1,2], instrument_control:true)    
        post "/api/v2/stores/config/imentore_copy/2_10/XPDEMO/10100/HEDGING", params: {'EnvironmentLocal':'1'}
        account_server = AccountServer.find_by(name: "xpdemo")

        expect(AccountServer.all.size).to be == 2
        expect(Account.find_by(name: 10100, account_server_id:2).id).to be == 2
        expect(Account.find_by(name: 10100, account_server_id:1).account_server.name).to be == "darwinexdemo"
        expect(Account.where(name: 10100, account_server_id:2).last.account_server.name).to be == "xpdemo"
        expect(Account.find_by(name: 10100, account_server_id:2).account_server_id).to be == 2

        post "/api/v2/stores/config/imentore_copy/2_10/DarwinexDemo/564775/HEDGING", params: {'EnvironmentLocal':'1'} 
        post "/api/v2/stores/config/imentore_copy/2_10/XPDEMO/564775/HEDGING", params: {'EnvironmentLocal':'1'} 
        expect(response).to have_http_status 400
        expect(AccountServer.all.size).to be == 2
      end

      it 'Create AccountServer Name same STORE with different customer' do
        account_server = AccountServer.find_by(name: "xpdemo")
        post "/api/v2/stores/config/imentore_copy/2_10/DarwinexDemo/10100/HEDGING", params: {'EnvironmentLocal':'1'}
        @account_copy2 = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2])
        post "/api/v2/stores/config/imentore_copy/2_10/XPDEMO/10100/HEDGING", params: {'EnvironmentLocal':'1'}
        expect(response).to have_http_status 201
        expect(Account.all.size).to be == 2
        expect(AccountServer.all.size).to be == 2
        expect(AccountServer.find_by(name: "xpdemo").accounts.count).to be == 1
        expect(AccountServer.find_by(name: "darwinexdemo").accounts.count).to be == 1
        expect(Account.find_by(name: 10100, account_server_id:3).account_server.name).to be == "darwinexdemo"
        expect(Account.find_by(name: 10100, account_server_id:4).account_server.name).to be == "xpdemo"
        expect(Account.find_by(name: 10100, account_server_id:3).store_id).to be == 1
        expect(Account.find_by(name: 10100, account_server_id:4).store_id).to be == 1

        account_server = AccountServer.find_by(name: "darwinexdemo")
        @store2 = create(:store, :store2, plan_id: @plan1.id)
        @customer2 = create(:customer, :customer2, store:@store, user:@user_customer)
        @account_copy2 = create(:account, :copy2, store: @store2, customer:@customer2, meta_margin_mode: 'hedging', trace_ids: [1,2], instrument_control:true)    
        post "/api/v2/stores/config/imentore_copy/2_10/DarwinexDemo/10100/HEDGING", params: {'EnvironmentLocal':'1'}
        expect(Account.all.size).to be == 3
        expect(AccountServer.all.size).to be == 2
        expect(AccountServer.find_by(name: "xpdemo").accounts.count).to be == 1
        expect(AccountServer.find_by(name: "darwinexdemo").accounts.count).to be == 1

        post "/api/v2/stores/config/imentore_copy/2_10/DarwinexDemo/10200/HEDGING", params: {'EnvironmentLocal':'1'}
        expect(response).to have_http_status 201

        expect(Account.all.size).to be == 3
        expect(AccountServer.all.size).to be == 2
        expect(AccountServer.find_by(name: "xpdemo").accounts.count).to be == 1
        expect(AccountServer.find_by(name: "darwinexdemo").accounts.count).to be == 2
        expect(Account.where(name: 10200, account_server_id:3, store_id:2).last.account_server.name).to be == "darwinexdemo"
        expect(Account.where(name: 10200, account_server_id:3).last.store_id).to be == 2
      end


      it 'Account duplicate same Store' do
        account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging') 
        expect(account1.account_server).to be_nil
        account_dup = build(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
        expect(account_dup.account_server).to be_nil
        expect(account_dup).to_not be_valid
        expect(account_dup.errors.attribute_names).to be == [:name]
        
        post "/api/v2/stores/config/imentore_slave/2_22/DarwinexDemo/20100/HEDGING", params: {'EnvironmentLocal':'1'}
        account1.reload
        expect(account1).to be_valid
        expect(account1.account_server.name).to be == "darwinexdemo"
        
        account_dup = build(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
        expect(account_dup.account_server).to be_nil
        account_dup.valid?
      end
    
    end
  end

end