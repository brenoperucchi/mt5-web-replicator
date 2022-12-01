# 334199527
require 'rails_helper'

RSpec.describe "PLanStore" do
  before(:context) do
    @plan = create(:plan)
    @store = create(:store, plan_id: @plan.id)
    @trace = create(:trace, :copy, store: @store)
    @admin = create(:customer, :admin, store:@store)
    @customer = create(:customer, :client, store:@store)
    @account_copy = create(:account, :copy, store: @store, customer:@customer,meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')    
  end

  describe "Plan Usage", focus: true do
    context 'POST' do
      it 'Hedging - Verify Slave has orders and before delete 1 order the count was correctly' do 
        date_today = DateTime.now
        invoice_name = "#{@store.id}-#{date_today.strftime("%Y-%m")}"
        @store.create_invoice_month
        @invoice = @store.invoices.first
        expect(@invoice.name).to be == invoice_name
        expect(@invoice.items.count).to be == 4
        expect(@invoice.amount.to_f).to be == 97.23
      end
    end
  end
end