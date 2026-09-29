require 'rails_helper'

# Regression for rails/rails#46934: on Ruby >= 3.0 the `state_machine` gem's
# `def save(*) ... { super }` override turned Rails' `save(**options)` keyword
# arguments into a positional hash, raising
# "ArgumentError: wrong number of arguments (given 1, expected 0)" from
# ActiveRecord::Suppressor#save on every create/find_or_create_by.
RSpec.describe Order, type: :model do
  let(:plan) { create(:plan, :plan1) }
  let(:store) { create(:store, plan_id: plan.id) }
  let(:payment) { create(:payment, payment_method: create(:payment_method, :stripe), store: store) }
  let(:customer_plan) { create(:customer_plan, payment: payment, store: store) }
  let(:trace) { create(:trace, :copy, stores: [store], customer_plans: [customer_plan]) }
  let(:customer) { create(:customer, :customer, user: create(:user, :customer, store: store)) }
  let(:account) do
    create(:account, :copy, store: store, customer: customer, trace_ids: [trace.id], account_server: create(:account_server))
  end

  it 'saves with keyword options' do
    order = build(:order, trace: trace, account: account, store: store)

    expect(order.save(validate: false)).to be(true)
    expect(order.save!(validate: true)).to be(true)
  end

  # Mirrors Model::TraceService#create_order (netting branch).
  it 'creates through the account association' do
    order = account.orders.create(trace: trace, content_id: 20000001, symbol: 'EURUSD', account: account, store: store)

    expect(order).to be_persisted
    expect(order.state).to eq('pending')
  end

  # Mirrors Model::TraceService#create_order (hedging branch).
  it 'finds or creates with create_with' do
    order = Order.create_with(trace: trace, content_id: 20000002, symbol: 'EURUSD', account: account, store: store)
                 .find_or_create_by(content_id: 20000002, trace: trace, store: store)

    expect(order).to be_persisted
    expect(Order.create_with(symbol: 'GBPUSD').find_or_create_by(content_id: 20000002, trace: trace, store: store)).to eq(order)
  end
end
