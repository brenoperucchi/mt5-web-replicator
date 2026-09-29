require 'rails_helper'

RSpec.describe PaymentMethod::Stripe do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @payment = @store.payments.first
    @customer = create(:customer, :customer, user: create(:user, :customer, store: @store))
  end

  let(:invoice) do
    Invoice.create!(name: 'stripe-spec', store: @store, payment: @payment, invoiceable: @customer, amount: 53.33)
  end

  describe '#checkout' do
    it 'creates a Checkout Session in cents and returns its URL' do
      stub = stub_stripe_checkout_session_create
      url = described_class.new(@payment).checkout(invoice)

      expect(url).to be == 'https://checkout.stripe.com/c/pay/cs_test_123'
      expect(invoice.reload.response[:checkout_session_id]).to be == 'cs_test_123'
      expect(stub.with { |req|
        body = Rack::Utils.parse_nested_query(req.body)
        item = body['line_items']['0']
        req.headers['Authorization'] == 'Bearer sk_test_x' &&
          body['mode'] == 'payment' &&
          body['client_reference_id'] == invoice.id.to_s &&
          item['price_data']['unit_amount'] == '5333' &&
          item['price_data']['currency'] == 'usd' &&
          body['success_url'] == "https://#{@store.domain_url}/payments/#{invoice.id}/return/success?session_id={CHECKOUT_SESSION_ID}" &&
          body['cancel_url'] == "https://#{@store.domain_url}/payments/#{invoice.id}/return/cancel"
      }).to have_been_requested
    end

    it 'uses PAYMENT_CURRENCY when set' do
      stub = stub_stripe_checkout_session_create
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('PAYMENT_CURRENCY', 'usd').and_return('EUR')
      described_class.new(@payment).checkout(invoice)
      expect(stub.with { |req|
        Rack::Utils.parse_nested_query(req.body).dig('line_items', '0', 'price_data', 'currency') == 'eur'
      }).to have_been_requested
    end
  end

  describe 'Invoice#invoice_send' do
    it 'stores the hosted checkout URL as the payment link' do
      stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_test_123'
      expect(invoice.reload.payment_link).to be == 'https://checkout.stripe.com/c/pay/cs_test_123'
      expect(invoice.redirect_url).to be == invoice.payment_link
    end
  end

  describe 'checkout idempotency' do
    let(:sessions_url) { "#{StripeHelpers::STRIPE_API}/checkout/sessions" }

    it 'reuses the open session on a second send instead of creating another' do
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_test_123'
      stub_stripe_checkout_session_retrieve(id: 'cs_test_123', status: 'open', url: 'https://checkout.stripe.com/c/pay/cs_test_123')
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_test_123'
      expect(create_stub).to have_been_requested.once
    end

    it 'does not create a session for a paid invoice' do
      create_stub = stub_stripe_checkout_session_create
      invoice.update_columns(state: Invoice.states[:paid])
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
    end

    it 'does not create a session for a refunded invoice' do
      create_stub = stub_stripe_checkout_session_create
      invoice.update_columns(state: Invoice.states[:refunded])
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
    end

    it 'creates a new session with a new idempotency key when the previous one expired' do
      invoice.update(response: { checkout_session_id: 'cs_old', checkout_attempt: 1 })
      stub_stripe_checkout_session_retrieve(id: 'cs_old', status: 'expired', url: nil)
      create_stub = stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'
      expect(a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => "invoice-#{invoice.id}-attempt-2" })).to have_been_made.once
      expect(invoice.reload.response[:checkout_session_id]).to be == 'cs_new'
    end

    it 'marks the invoice paid instead of charging again when the previous session completed' do
      invoice.update(response: { checkout_session_id: 'cs_done', checkout_attempt: 1 })
      stub_stripe_checkout_session_retrieve(id: 'cs_done', status: 'complete', payment_status: 'paid', url: nil,
                                            metadata: { invoice_id: invoice.id.to_s })
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
      expect(invoice.reload.state).to be == 'paid'
    end

    it 'sends a stable idempotency key on the first attempt' do
      stub_stripe_checkout_session_create
      invoice.invoice_send
      expect(a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => "invoice-#{invoice.id}-attempt-1" })).to have_been_made.once
    end
  end

  describe 'Stripe errors' do
    it 'returns false from invoice_send when Stripe rejects the request' do
      stub_request(:post, "#{StripeHelpers::STRIPE_API}/checkout/sessions")
        .to_return(status: 401, headers: { 'Content-Type' => 'application/json' },
                   body: { error: { type: 'invalid_request_error', message: 'Invalid API Key provided' } }.to_json)
      expect(invoice.invoice_send).to be false
      expect(invoice.reload.payment_link).to be_blank
    end

    it 'does not create a session for an amount below one cent' do
      create_stub = stub_stripe_checkout_session_create
      invoice.update_columns(amount: 0)
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
    end
  end

  describe 'PaymentMethod#provider' do
    it 'builds a provider bound to each payment (no memoization across payments)' do
      method = @payment.payment_method
      other = Payment.create!(payment_method: method, store: @store, api_token: 'sk_test_other')
      expect(method.provider(@payment).api_key).to be == 'sk_test_x'
      expect(method.provider(other).api_key).to be == 'sk_test_other'
    end

    it 'returns nil for a handle without a provider' do
      expect(PaymentMethod.new(handle: 'mercado_pago').provider(@payment)).to be_nil
    end
  end
end
