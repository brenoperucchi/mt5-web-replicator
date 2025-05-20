require 'rails_helper'

RSpec.describe "Account" do
  before(:context) do
    travel_to Date.parse("2022-11-01")
    freeze_time
    @plan1 = create(:plan, :plan1)
    @plan2 = create(:plan, :plan2)
    @store = create(:store, plan_id: @plan1.id)
    @plan_method = create(:payment_method, :mercadopago)
    @payment = create(:payment, payment_method: @plan_method, store: @store)
    @customer_plan = create(:customer_plan, payment: @payment, store:@store)
    @trace = create(:trace, :copy, stores: [@store], customer_plans:[@customer_plan])
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, user:@user_admin)
    @customer = create(:customer, :customer, user:@user_customer)
    @account_copy = create(:account, :copy, store: @store, customer:@customer,meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
  end

  describe "Plan - insert discount value" do
    it 'Account duplicate same Store' do 
      @account_dup = build(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
      expect(@account_dup).to_not be_valid
      @account_dup.valid?
      expect(@account_dup.errors.attribute_names).to be == [:name]
    end

    it 'Account duplicate same Store' do 
      @account_dup = build(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
      expect(@account_dup).to_not be_valid
      @account_dup.valid?
      expect(@account_dup.errors.attribute_names).to be == [:name]

      account_server = AccountServer.find_or_create_by(name:"BROKERTEST")
      @account1.update(account_server: account_server)
      
      @account_dup = build(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
      expect(@account_dup).to be_valid
    end

    it 'Account duplicate same Store' do 
      account_server = AccountServer.find_or_create_by(name:"BROKERTEST")
      @account1.update(account_server: account_server)
      @account_dup = build(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
      expect(@account_dup).to be_valid
    end

    it 'Account duplicate another Store' do 
      @store2 = create(:store, :store2, plan_id: @plan2.id)
      @account_dup = build(:account, :slave1, store: @store2, customer:@customer, meta_margin_mode: 'hedging')    
      expect(@account_dup).to be_valid
    end
  end
end