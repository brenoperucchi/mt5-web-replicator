require 'rails_helper'

RSpec.describe ApplicationRecord, 'ransack hardening' do
  before(:context) do
    @plan = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan.id)
  end

  it 'ignores conditions that walk into payment credentials' do
    expect(Order.ransack(trace_stores_payments_api_token_start: 'x').result.count).to be == Order.count
    expect(Store.ransack(payments_api_token_start: 'nomatch').result.count).to be == Store.count
    expect(Invoice.ransack(payment_webhook_token_start: 'nomatch').result.count).to be == Invoice.count
  end

  # mt5-2 rev-2 N5: trace.stores crosses into other stores' customers (PII).
  it 'does not walk from a record into other stores customers' do
    expect(Order.ransack(trace_stores_customers_user_email_cont: 'x').result.count).to be == Order.count
    expect(Trace.ransackable_associations).not_to include('stores')
    expect(Store.ransackable_associations).not_to include('customers')
    expect(Customer.ransackable_associations).not_to include('user')
  end

  it 'does not expose secret columns' do
    expect(User.ransackable_attributes).not_to include('encrypted_password', 'reset_password_token')
    expect(Payment.ransackable_attributes).not_to include('api_token', 'webhook_token')
    expect(Store.ransackable_attributes).not_to include('settings')
    expect(Store.ransackable_associations).not_to include('payments', 'users')
  end
end
