require 'rails_helper'

# Regression: transaction_slaves.ordertype is an integer column; price_open
# compared it with the string "0", so market BUY rows carried the master price.
RSpec.describe TradeHelperService, '.api_request_attributes with a real TransactionSlave' do
  before do
    plan          = create(:plan, :plan1)
    @store        = create(:store, plan_id: plan.id)
    payment       = create(:payment, payment_method: create(:payment_method, :stripe), store: @store)
    customer_plan = create(:customer_plan, payment: payment, store: @store)
    @trace        = create(:trace, :copy, stores: [@store], customer_plans: [customer_plan])
    customer      = create(:customer, :customer, user: create(:user, :customer, store: @store))
    server        = create(:account_server)
    @account      = create(:account, :slave1, store: @store, customer: customer, meta_margin_mode: 'hedging', trace_ids: [@trace.id], account_server: server)
  end

  def slave_with(ordertype)
    order = Order.create!(symbol: 'EURUSD', content_id: 1001 + ordertype, account: @account, store: @store, trace: @trace, state: 'executed')
    TransactionSlave.create!(symbol: 'EURUSD', ticket_master: 1001 + ordertype, ordertype: ordertype, lot: 0.1,
                             price_request: 1.2345, account: @account, trace: @trace, store: @store, order: order, state: 'pending')
  end

  def price_field(slave)
    described_class.api_request_attributes(slave.reload, slave).split('|')[7]
  end

  it 'sends "0" (market) for a BUY market order' do
    expect(price_field(slave_with(0))).to eq('0')
  end

  it 'sends "0" (market) for a SELL market order' do
    expect(price_field(slave_with(1))).to eq('0')
  end

  it 'sends the requested price for pending orders' do
    expect(price_field(slave_with(2)).to_f).to eq(1.2345)
  end
end
