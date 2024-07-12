# 334199527
require 'rails_helper'

RSpec.describe "PLanStore" do#, focus:true do
  before(:context) do
    travel_to Date.parse("2022-11-01")
    freeze_time
    @plan1 = create(:plan, :plan1)
    @plan2 = create(:plan, :plan2)
    @store = create(:store, plan_id: @plan1.id)
    @trace = create(:trace, :copy, stores: [@store])
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, user:@user_admin)
    @customer = create(:customer, :customer, user:@user_customer)
    @account_copy = create(:account, :copy, store: @store, customer:@customer,meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
  end

  describe "Plan - insert discount value" do
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-01")
      @store.create_invoice_month
      @invoice = @store.invoices.first
      expect(Plan.first.amount_discount.to_f).to be == 50.0
      expect(@invoice.name).to be == "1-2022-11"
      expect(@invoice.items.count).to be == 4
      expect(@invoice.amount.to_f).to be == 140.00
      travel_to Date.parse("2022-12-01")
      Plan.first.update(settings:{"discount":30})
      expect(Plan.first.amount_discount.to_f).to be == 35.0
      @store.create_invoice_month
      @invoice = @store.invoices.find_by(name:"1-2022-12")
      expect(@invoice.name).to be == "1-2022-12"
      expect(@invoice.items.count).to be == 4
      expect(@invoice.amount.to_f).to be == 125.00
    end
  end
  describe "Plan Item without amount" do
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-01")
      Plan.first.plan_items.update_all(amount:nil)
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
  describe "Plan Item amount change from plan amount_extra" do
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-01")
      Plan.first.plan_items.update_all(amount:15)
      @store.create_invoice_month
      @invoice = @store.invoices.first
      expect(@invoice.name).to be == "1-2022-11"
      expect(@invoice.items.count).to be == 4
      expect(@invoice.amount.to_f).to be == 95.00
      @account3 = create(:account, :slave3, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
      travel_to Date.parse("2022-12-01")
      @store.create_invoice_month
      @invoice = @store.invoices.find_by(name:"1-2022-12")
      expect(@invoice.name).to be == "1-2022-12"
      expect(@invoice.items.count).to be == 5
      expect(@invoice.amount.to_f).to be == 110.00
    end
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
        travel_to Date.parse("2022-12-16")
        @store.update(plan:@plan2)
        travel_to Date.parse("2022-12-20")
        @store.disable_store
        travel_to Date.parse("2022-12-30")
        @store.create_invoice_month
        @invoice = @store.invoices.first
        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 133.55
      end
    end

    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        travel_to Date.parse("2022-11-01")
        freeze_time
        @account3 = create(:account, :slave3, store: @store, customer:@customer, meta_margin_mode: 'hedging')
        travel_to Date.parse("2022-11-30")
        freeze_time
        @account2.soft_destroy
        travel_to Date.parse("2022-11-01")
        freeze_time
        @store.create_invoice_month
        @invoice = @store.invoices.find_by(name:"1-2022-11")
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 169.0
        travel_to Date.parse("2022-12-17")
        freeze_time
        @account3.soft_destroy
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
      it 'Account with Travel Date Forward' do 
        travel_to Date.parse("2022-12-01")
        freeze_time
        travel_to Date.parse("2022-12-15")
        freeze_time
        @account3 = create(:account, :slave3, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
        @store.create_invoice_month(true, nil)
        @invoice = @store.invoices.first
        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 93.22
        @store.accounts.find(3).soft_destroy
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
  describe "Remove Customer" do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        travel_to Date.parse("2022-12-01")
        freeze_time
        travel_to Date.parse("2022-12-15")
        freeze_time
        @account3 = create(:account, :slave3, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
        @store.create_invoice_month(true, nil)
        @invoice = @store.invoices.first

        expect(@invoice.name).to be == "1-2022-12"
        expect(@invoice.items.count).to be == 5
        expect(@invoice.amount.to_f).to be == 93.22
        @store.accounts.find(3).soft_destroy
        travel_to Date.parse("2023-01-01")
        freeze_time
        @customer.soft_destroy
        @store.create_invoice_month
        @invoice = @store.invoices.find_by(name:"1-2023-01")
        expect(@invoice.name).to be == "1-2023-01"
        expect(@invoice.items.count).to be == 4
        expect(@invoice.amount.to_f).to be == 140.00
      end
    end
  end
end