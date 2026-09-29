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

  it 'does not expose secret columns' do
    expect(User.ransackable_attributes).not_to include('encrypted_password', 'reset_password_token')
    expect(Payment.ransackable_attributes).not_to include('api_token', 'webhook_token')
    expect(Store.ransackable_attributes).not_to include('settings')
    expect(Store.ransackable_associations).not_to include('payments', 'users')
  end
end
