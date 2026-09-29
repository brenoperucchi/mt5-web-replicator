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

  # mt5-2 rev-1 #3: the panel offers "Pagamento" for denied invoices too.
  it 'repoints denied invoices and clears their payment link' do
    denied = Invoice.create!(name: 'denied', store: store, payment: legacy, amount: 10, state: :denied,
                             payment_link: 'https://mp/denied')
    expect { run }.to output(/invoices_repointed=2/).to_stdout
    expect(denied.reload.payment.payment_method.handle).to be == 'stripe'
    expect(denied.payment_link).to be_nil
  end

  # mt5-2 rev-2 N3
  it 'reports reused Stripe payments with credentials, flagging malformed ones, also in DRY_RUN' do
    stripe_method = PaymentMethod.create!(name: 'Stripe', handle: 'stripe')
    bad = Payment.create!(payment_method: stripe_method, store: store, api_token: 'TEST-000', webhook_token: 'whsec_ok')
    later = Payment.create!(payment_method: stripe_method, store: store, api_token: 'sk_live_later')

    output = capture_stdout { run(dry_run: '1') }
    expect(output).to match(/Payment##{bad.id} .*api_token=INVALID.*webhook_token=ok/)
    expect(output).not_to include("Payment##{later.id} ")
    expect(output).not_to include('TEST-000') # never print secrets
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
