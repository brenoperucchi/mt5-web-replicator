require 'rails_helper'

RSpec.describe Store, 'payment provider selection' do
  before(:context) do
    @plan = create(:plan, :plan1)
    @mercado_pago = PaymentMethod.create!(name: 'MercadoPago', handle: 'mercado_pago')
    @stripe = PaymentMethod.create!(name: 'Stripe', handle: 'stripe')
  end

  it 'associates only available providers and defaults the customer plan to Stripe' do
    store = Store.create!(name: 'Selection', email: 'selection@store.com', url: 'selection', plan: @plan)
    store.create_association_after_create('owner@selection.com', '123123')

    expect(store.payment_methods.reload).to contain_exactly(@stripe)
    expect(store.customer_plans.first.payment.payment_method).to be == @stripe
  end

  it 'exposes only providers with an adapter' do
    expect(PaymentMethod.available).to contain_exactly(@stripe)
    expect(@mercado_pago.available?).to be false
    expect(@stripe.available?).to be true
  end

  it 'bills the monthly store invoice through an available provider' do
    store = Store.create!(name: 'Monthly', email: 'monthly@store.com', url: 'monthly', plan: @plan)
    legacy = Payment.create!(payment_method: @mercado_pago, store: store)
    stripe = Payment.create!(payment_method: @stripe, store: store)
    store.update_column(:payment_id, legacy.id)

    store.create_invoice_month
    expect(store.invoices.last.payment).to be == stripe
  end

  # mt5-2 rev-1 #2
  it "never bills a store through another store's payment" do
    other = Store.create!(name: 'Other', email: 'other@store.com', url: 'other', plan: @plan)
    foreign = Payment.create!(payment_method: @stripe, store: other, api_token: 'sk_other')
    store = Store.create!(name: 'Legacy FK', email: 'legacyfk@store.com', url: 'legacyfk', plan: @plan)
    own = Payment.create!(payment_method: @stripe, store: store)
    store.update_column(:payment_id, foreign.id)

    expect(store.reload.billing_payment).to be == own
    store.create_invoice_month
    expect(store.invoices.last.payment).to be == own
  end

  it 'points a new store at its own default payment' do
    store = Store.create!(name: 'Own', email: 'own@store.com', url: 'own', plan: @plan)
    store.create_association_after_create('owner@own.com', '123123')
    expect(store.reload.payment).to be_present
    expect(store.payment.store_id).to be == store.id
  end
end
