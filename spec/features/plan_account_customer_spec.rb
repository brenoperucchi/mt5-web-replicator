require 'rails_helper'

RSpec.describe "PlanAccountCustomer" do
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
    @customer = create(:customer, :customer, store:@store, user:@user_customer, customer_plan_ids:[1])
    @account_copy = create(:account, :copy, store: @store, customer:@customer,meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging', contract_volume: 1)
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
  end

  describe "Plan - insert discount value" do
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-01")
      date_today = DateTime.now
      expect(@trace.customer_plan.amount.to_f).to be == 100.0
      @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
      @account1.create_invoice_account(@trace, false, nil)
      name = "#{@account1.id}-#{date_today.strftime("%Y-%m")}"
      invoice = @store.invoice_stores.find_by(name: name)
      expect(invoice.amount.to_f).to be == 100.0
    end
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-15")
      date_today = DateTime.now
      expect(@trace.customer_plan.amount.to_f).to be == 100.0
      @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
      @account1.create_invoice_account(@trace, false, nil)
      name = "#{@account1.id}-#{date_today.strftime("%Y-%m")}"
      invoice = @store.invoice_stores.find_by(name: name)

      expect(invoice.name).to be == "2-2022-11"
      expect(invoice.amount.to_f).to be == 100.0
    end
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-15")
      date_today = DateTime.now
      expect(@trace.customer_plan.amount.to_f).to be == 100.0
      @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
      @account1.create_invoice_account(@trace, true, nil)
      name = "#{@account1.id}-#{date_today.strftime("%Y-%m")}"
      invoice = @store.invoice_stores.find_by(name: name)

      expect(invoice.name).to be == "2-2022-11"
      expect(invoice.amount.to_f).to be == 53.33
    end
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-01")
      date_today = DateTime.now
      expect(@trace.customer_plan.amount.to_f).to be == 100.0
      @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
      travel_to Date.parse("2022-12-31")
      @account1.create_invoice_account(@trace, false, "-1")
      name = "2-2022-11"  
      invoice = @store.invoice_stores.find_by(name: name)

      expect(invoice.name).to be == "2-2022-11"
      expect(invoice.amount.to_f).to be == 100.0
    end
    it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
      travel_to Date.parse("2022-11-01")
      date_today = DateTime.now
      expect(@trace.customer_plan.amount.to_f).to be == 100.0
      @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
      travel_to Date.parse("2022-12-16")
      @account1.create_invoice_account(@trace, true, "-1")
      name = "2-2022-11"  
      invoice = @store.invoice_stores.find_by(name: name)

      expect(invoice.name).to be == "2-2022-11"
      expect(invoice.amount.to_f).to be == 50.00
    end
    
    describe "with valid params" do
      it "Store 2 with date Proportional", focus:true do
        @customer_plan = @store.customer_plans.first
        @customer_plan.update(amount: 4)
        @customer_plan.payment.update(min_amount: 5)
        @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
        @account1.create_invoice_account(@trace, true)
        # expect(@trace.customer_plan.amount.to_f).to be == 5
        # binding.pry
        expect(@customer_plan.calculate_amount).to be == 5
      end
      it "Store 2 with date Proportional", focus:true do
        @customer_plan = @store.customer_plans.first
        @customer_plan.update(amount: 4)
        @customer_plan.payment.update(min_amount: 5)
        @account1.update(contract_volume: 2)
        @account1.add_account_trace_to_planusage(@trace, @trace.customer_plan.id)
        @account1.create_invoice_account(@trace, true)
        # expect(@trace.customer_plan.amount.to_f).to be == 5
        # binding.pry
        expect(@customer_plan.calculate_amount).to be == 5
      end
    end

  end
end

