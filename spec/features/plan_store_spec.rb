# 334199527
require 'rails_helper'

RSpec.describe "PLanStore" do
  before(:context) do
    travel_to Date.parse("2022-11-01")
    freeze_time
    @plan1 = create(:plan, :plan1)
    @plan2 = create(:plan, :plan2)
    @store = create(:store, plan_id: @plan1.id)
    @trace = create(:trace, :copy, store: @store)
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, store:@store, user:@user_admin)
    @customer = create(:customer, :customer, store:@store, user:@user_customer)
    @account_copy = create(:account, :copy, store: @store, customer:@customer,meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
  end

  describe "Plan 1" do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        travel_to Date.parse("2022-11-01")
        @store.create_invoice_month
        @invoice = @store.invoices.first
        expect(@invoice.name).to be == "1-2022-11"
        expect(@invoice.items.count).to be == 4
        expect(@invoice.amount.to_f).to be == 140.00
        travel_to Date.parse("2022-12-01")
        @store.create_invoice_month
        @invoice = @store.invoices.find_by(name:"1-2022-12")
        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 4
        expect(@invoice.amount.to_f).to be == 140.00


      end
    end
  end
  describe "Plan 1 Modify to 2" do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        travel_to Date.parse("2022-12-01")
        travel_to Date.parse("2022-12-15")
        @store.update(plan:@plan2)
        travel_to Date.parse("2022-12-31")
        @store.create_invoice_month
        @invoice = @store.invoices.first
        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 167.42
      end
    end
  end
  describe "Plan 1 remove and add another account to proportional" do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        travel_to Date.parse("2022-11-17")
        freeze_time
        @account2.destroy
        travel_to Date.parse("2022-11-23")
        @account3 = create(:account, :slave3, store: @store, customer:@customer, meta_margin_mode: 'hedging')
        travel_to Date.parse("2022-11-30")
        @store.create_invoice_month
        @invoice = @store.invoices.find_by(name:"1-2022-11")
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 134.00
        travel_to Date.parse("2022-12-17")
        freeze_time
        @account3.destroy
        travel_to Date.parse("2022-12-31")
        @store.create_invoice_month
        @invoice = @store.invoices.last
        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 4
        expect(@invoice.amount.to_f).to be == 125.48
      end
    end
  end
  describe "Plan 1 remove account and account and change month" do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        travel_to Date.parse("2022-12-01")
        freeze_time
        travel_to Date.parse("2022-12-15")
        freeze_time
        @account3 = create(:account, :slave3, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
        @store.create_invoice_month
        @invoice = @store.invoices.first
        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 156.45
        @store.accounts.find(3).destroy
        travel_to Date.parse("2023-01-01")
        freeze_time
        @store.create_invoice_month
        @invoice = @store.invoices.find_by(name:"1-2023-01")
        expect(@invoice.name).to be == "1-2023-01"
        expect(@invoice.items.count).to be == 4
        expect(@invoice.amount.to_f).to be == 140.00
      end
    end
  end
end