require 'rails_helper'
require 'rake'

RSpec.describe 'billing:migrate_mercadopago_to_stripe' do
  before(:context) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('billing:migrate_mercadopago_to_stripe')
    @plan = create(:plan, :plan1)
  end

  let(:task) { Rake::Task['billing:migrate_mercadopago_to_stripe'] }
  let(:mercado_pago) { PaymentMethod.create!(name: 'MercadoPago', handle: 'mercado_pago') }
  let(:store) { Store.create!(name: 'Legacy', email: 'legacy@store.com', url: 'legacy', plan: @plan) }
  let(:legacy) { Payment.create!(payment_method: mercado_pago, store: store, api_token: 'mp_token') }
  let!(:plan) { store.customer_plans.create!(name: 'P', amount: 10, kind: 'fixed', payment: legacy, due_at_dates: 5) }
  let!(:open_invoice) do
    Invoice.create!(name: 'open', store: store, payment: legacy, amount: 10, state: :to_paid, payment_link: 'https://mp/old')
  end
  let!(:paid_invoice) { Invoice.create!(name: 'paid', store: store, payment: legacy, amount: 10, state: :paid) }

  before do
    store.update_column(:payment_id, legacy.id)
    task.reenable
  end

  def run(dry_run: nil)
    old = ENV['DRY_RUN']
    ENV['DRY_RUN'] = dry_run
    task.invoke
  ensure
    ENV['DRY_RUN'] = old
  end

  it 'repoints the store, its customer plans and open invoices to a Stripe payment' do
    expect { run }.to output(/stores_repointed=1, customer_plans_repointed=1, invoices_repointed=1/).to_stdout

    stripe = Payment.joins(:payment_method).find_by(store: store, payment_methods: { handle: 'stripe' })
    expect(stripe).to be_present
    expect(stripe.api_token).to be_blank
    expect(store.reload.payment).to be == stripe
    expect(plan.reload.payment).to be == stripe
    expect(open_invoice.reload.payment).to be == stripe
    expect(open_invoice.payment_link).to be_nil
    expect(paid_invoice.reload.payment).to be == legacy
    expect(PaymentMethod.exists?(mercado_pago.id)).to be true
    expect(Payment.exists?(legacy.id)).to be true
  end

  it 'is idempotent' do
    expect { run }.to output.to_stdout
    task.reenable
    expect { run }.to output(/stripe_payments_created=0, stores_repointed=0, customer_plans_repointed=0, invoices_repointed=0/).to_stdout
    expect(Payment.where(store: store).count).to be == 2
  end

  it 'writes nothing with DRY_RUN=1' do
    expect { run(dry_run: '1') }.to output(/DRY RUN.*invoices_repointed=1/).to_stdout
    expect(store.reload.payment).to be == legacy
    expect(open_invoice.reload.payment).to be == legacy
    expect(Payment.where(store: store).count).to be == 1
  end
end
