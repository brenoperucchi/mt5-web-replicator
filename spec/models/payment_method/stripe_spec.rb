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
      expect(a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => "test-invoice-#{invoice.id}-attempt-2" })).to have_been_made.once
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
      expect(a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => "test-invoice-#{invoice.id}-attempt-1" })).to have_been_made.once
    end

    # mt5-2 rev-1 #1 / rev-2 N2: boleto-like async methods finish the session
    # as complete/unpaid until the payment clears.
    it 'does not open a second checkout while an async payment is pending (complete/unpaid)' do
      invoice.update(response: { checkout_session_id: 'cs_async', checkout_attempt: 1 })
      stub_stripe_checkout_session_retrieve(id: 'cs_async', status: 'complete', payment_status: 'unpaid', url: nil,
                                            metadata: { invoice_id: invoice.id.to_s })
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
      expect(invoice.reload.state).not_to be == 'paid'
      expect(invoice.response[:checkout_session_id]).to be == 'cs_async'
    end

    # Blocker A (scout mt5-1): the failure must be recorded for this session;
    # a `denied` invoice alone (legacy data without checkout_status) waits.
    it 'allows a new attempt after the async payment of the current session failed' do
      invoice.update(response: { checkout_session_id: 'cs_async', checkout_attempt: 1, checkout_status: 'failed' })
      invoice.update_columns(state: Invoice.states[:denied])
      stub_stripe_checkout_session_retrieve(id: 'cs_async', status: 'complete', payment_status: 'unpaid', url: nil,
                                            metadata: { invoice_id: invoice.id.to_s })
      stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'
      expect(a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => "test-invoice-#{invoice.id}-attempt-2" })).to have_been_made.once
    end

    # mt5-2 rev-1 #1: a failed lookup says nothing about the previous session.
    it 'does not create a session when the previous one cannot be retrieved' do
      invoice.update(response: { checkout_session_id: 'cs_unknown', checkout_attempt: 1 })
      stub_request(:get, "#{sessions_url}/cs_unknown")
        .to_return(status: 500, headers: { 'Content-Type' => 'application/json' },
                   body: { error: { type: 'api_error', message: 'boom' } }.to_json)
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
      expect(invoice.reload.response[:checkout_attempt]).to be == 1
      expect(invoice.response[:checkout_session_id]).to be == 'cs_unknown'
    end

    # mt5-2 rev-1 #4: an open session is only reused for the same amount/currency.
    context 'when the invoice amount changed since the open session was created' do
      before do
        invoice.update(response: { checkout_session_id: 'cs_old', checkout_attempt: 1,
                                   checkout_amount_cents: 5333, checkout_currency: 'usd' })
        stub_stripe_checkout_session_retrieve(id: 'cs_old', status: 'open', url: 'https://checkout.stripe.com/c/pay/cs_old')
        invoice.update_columns(amount: 60)
      end

      it 'expires the old session and creates a new one with a new key' do
        expire_stub = stub_request(:post, "#{sessions_url}/cs_old/expire")
          .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                     body: { id: 'cs_old', object: 'checkout.session', status: 'expired' }.to_json)
        stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')

        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'
        expect(expire_stub).to have_been_requested.once
        expect(a_request(:post, sessions_url).with { |req|
          req.headers['Idempotency-Key'] == "test-invoice-#{invoice.id}-attempt-2" &&
            Rack::Utils.parse_nested_query(req.body).dig('line_items', '0', 'price_data', 'unit_amount') == '6000'
        }).to have_been_made.once
        expect(invoice.reload.response).to include(checkout_session_id: 'cs_new', checkout_amount_cents: 6000,
                                                   checkout_currency: 'usd')
      end

      it 'does not issue a second checkout when the old session cannot be expired' do
        stub_request(:post, "#{sessions_url}/cs_old/expire")
          .to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                     body: { error: { type: 'invalid_request_error', message: 'already complete' } }.to_json)
        create_stub = stub_stripe_checkout_session_create
        expect(invoice.invoice_send).to be false
        expect(create_stub).not_to have_been_requested
      end
    end

    it 'reuses the open session when amount and currency are unchanged' do
      invoice.update(response: { checkout_session_id: 'cs_old', checkout_attempt: 1,
                                 checkout_amount_cents: 5333, checkout_currency: 'usd' })
      stub_stripe_checkout_session_retrieve(id: 'cs_old', status: 'open', url: 'https://checkout.stripe.com/c/pay/cs_old')
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_old'
      expect(create_stub).not_to have_been_requested
      expect(a_request(:post, %r{/expire})).not_to have_been_made
    end
  end

  # Scout analysis mt5-1, blocker A: a failure is tracked per checkout attempt
  # (session), never inferred from a durable invoice state such as `denied`.
  describe 'attempt lifecycle' do
    let(:sessions_url) { "#{StripeHelpers::STRIPE_API}/checkout/sessions" }
    let(:provider) { described_class.new(@payment) }

    def deliver(type, id, payment_status: 'unpaid', status: 'complete')
      object = { id: id, object: 'checkout.session', status: status, payment_status: payment_status,
                 client_reference_id: invoice.id.to_s, metadata: { invoice_id: invoice.id.to_s } }
      payload = stripe_event_payload(type, object)
      request = double(raw_post: payload, headers: { 'Stripe-Signature' => stripe_signature_header(payload) })
      provider.handle_webhook(request)
      invoice.reload
    end

    def retrieve_as(id, status:, payment_status: 'unpaid', url: nil)
      stub_stripe_checkout_session_retrieve(id: id, status: status, payment_status: payment_status, url: url,
                                            amount_total: 5333, currency: 'usd',
                                            metadata: { invoice_id: invoice.id.to_s })
    end

    def key(n) = "test-invoice-#{invoice.id}-attempt-#{n}"
    def creates_with(n) = a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => key(n) })

    it '(1) after S1 failed and S2 was issued, S2 pending (complete/unpaid) blocks a third session' do
      stub_stripe_checkout_session_create(id: 'cs_1', url: 'https://checkout.stripe.com/c/pay/cs_1')
      expect(invoice.invoice_send).to be_present
      deliver('checkout.session.async_payment_failed', 'cs_1')
      expect(invoice.state).to be == 'denied'

      retrieve_as('cs_1', status: 'complete')
      stub_stripe_checkout_session_create(id: 'cs_2', url: 'https://checkout.stripe.com/c/pay/cs_2')
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_2'

      retrieve_as('cs_2', status: 'complete')
      expect(invoice.invoice_send).to be false
      expect(creates_with(3)).not_to have_been_made
      expect(invoice.reload.response).to include(checkout_session_id: 'cs_2', checkout_status: 'processing')
    end

    it '(2) a migrated denied invoice without a session gets one attempt, then waits while it is pending' do
      invoice.update_columns(state: Invoice.states[:denied])
      stub_stripe_checkout_session_create(id: 'cs_1', url: 'https://checkout.stripe.com/c/pay/cs_1')
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_1'
      expect(invoice.reload.response[:checkout_status]).to be == 'open'

      retrieve_as('cs_1', status: 'complete')
      expect(invoice.invoice_send).to be false
      expect(creates_with(1)).to have_been_made.once
      expect(creates_with(2)).not_to have_been_made
    end

    context 'with S2 as the current attempt after S1 failed' do
      before do
        invoice.update(response: { checkout_session_id: 'cs_2', checkout_attempt: 2, checkout_status: 'open',
                                   checkout_amount_cents: 5333, checkout_currency: 'usd',
                                   checkout_idempotency_key: key(2) })
        invoice.update_columns(state: Invoice.states[:denied])
      end

      it '(3) a confirmed failure of S2 releases exactly one next attempt' do
        deliver('checkout.session.async_payment_failed', 'cs_2')
        expect(invoice.response[:checkout_status]).to be == 'failed'
        retrieve_as('cs_2', status: 'complete')
        stub_stripe_checkout_session_create(id: 'cs_3', url: 'https://checkout.stripe.com/c/pay/cs_3')
        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_3'

        retrieve_as('cs_3', status: 'complete')
        expect(invoice.invoice_send).to be false
        expect(creates_with(3)).to have_been_made.once
        expect(creates_with(4)).not_to have_been_made
      end

      it '(4) a successful S2 blocks any new checkout' do
        deliver('checkout.session.async_payment_succeeded', 'cs_2', payment_status: 'paid')
        expect(invoice.state).to be == 'paid'
        expect(invoice.response[:checkout_status]).to be == 'paid'
        create_stub = stub_stripe_checkout_session_create
        expect(invoice.invoice_send).to be false
        expect(create_stub).not_to have_been_requested
      end

      it '(5) late failed/expired events of S1 do not release a new attempt while S2 is processing' do
        deliver('checkout.session.completed', 'cs_2')
        expect(invoice.response[:checkout_status]).to be == 'processing'
        deliver('checkout.session.async_payment_failed', 'cs_1')
        deliver('checkout.session.expired', 'cs_1', status: 'expired')
        expect(invoice.response).to include(checkout_session_id: 'cs_2', checkout_status: 'processing')

        retrieve_as('cs_2', status: 'complete')
        create_stub = stub_stripe_checkout_session_create
        expect(invoice.invoice_send).to be false
        expect(create_stub).not_to have_been_requested
      end
    end

    # Scout consultation mt5-2, blocker: two webhook handlers may load the
    # invoice before either saves. The decision must be made on the row read
    # under lock, never on a stale in-memory instance.
    context 'with stale invoice instances (overlapping webhooks)' do
      def session_obj(id, status: 'complete', payment_status: 'unpaid')
        ::Stripe::Checkout::Session.construct_from(
          id: id, object: 'checkout.session', status: status, payment_status: payment_status,
          client_reference_id: invoice.id.to_s, metadata: { invoice_id: invoice.id.to_s })
      end

      def apply(inst, id, type)
        provider.send(:apply_session, inst, session_obj(id), type)
      end

      it 'a late completed/unpaid applied through a stale instance does not undo a recorded failure' do
        invoice.update(response: { checkout_session_id: 'cs_2', checkout_attempt: 2, checkout_status: 'open',
                                   checkout_amount_cents: 5333, checkout_currency: 'usd',
                                   checkout_idempotency_key: key(2) })
        invoice.update_columns(state: Invoice.states[:to_paid])
        a = Invoice.find(invoice.id)
        b = Invoice.find(invoice.id)

        apply(a, 'cs_2', 'checkout.session.async_payment_failed')
        apply(b, 'cs_2', 'checkout.session.completed')

        invoice.reload
        expect(invoice.response[:checkout_status]).to be == 'failed'
        expect(invoice.state).to be == 'denied'

        retrieve_as('cs_2', status: 'complete')
        stub_stripe_checkout_session_create(id: 'cs_3', url: 'https://checkout.stripe.com/c/pay/cs_3')
        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_3'
        expect(creates_with(3)).to have_been_made.once
        expect(creates_with(4)).not_to have_been_made
      end

      it 'a stale instance loaded while S1 was current does not overwrite S2' do
        invoice.update(response: { checkout_session_id: 'cs_1', checkout_attempt: 1, checkout_status: 'open',
                                   checkout_amount_cents: 5333, checkout_currency: 'usd',
                                   checkout_idempotency_key: key(1) })
        invoice.update_columns(state: Invoice.states[:to_paid])
        stale = Invoice.find(invoice.id)

        s2 = { checkout_session_id: 'cs_2', checkout_attempt: 2, checkout_status: 'open',
               checkout_amount_cents: 5333, checkout_currency: 'usd', checkout_idempotency_key: key(2) }
        invoice.update!(response: invoice.response.merge(s2))

        apply(stale, 'cs_1', 'checkout.session.completed')
        expect(invoice.reload.response).to include(s2)
      end
    end

    # Scout analysis mt5-1, follow-up F1: a lost create response is retried
    # with the same key and parameters, never with a new attempt.
    context 'when the create response is lost after renewing an expired session' do
      before do
        invoice.update(response: { checkout_session_id: 'cs_old', checkout_attempt: 1, checkout_status: 'open',
                                   checkout_amount_cents: 5333, checkout_currency: 'usd' })
        retrieve_as('cs_old', status: 'expired')
        stub_request(:post, sessions_url).to_timeout
        expect(invoice.invoice_send).to be false
        expect(invoice.reload.response).to include(checkout_attempt: 2, checkout_status: 'creating',
                                                   checkout_idempotency_key: key(2), checkout_amount_cents: 5333)
      end

      it 'retries with the same idempotency key and parameters' do
        stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
        retrieve_as('cs_new', status: 'open', url: 'https://checkout.stripe.com/c/pay/cs_new')
        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'
        expect(creates_with(2)).to have_been_made.twice
        expect(creates_with(3)).not_to have_been_made
        expect(invoice.reload.response).to include(checkout_session_id: 'cs_new', checkout_attempt: 2,
                                                   checkout_status: 'open')
      end

      # Chosen behavior: the pending create is first recovered with its
      # original key/amount (Stripe returns the same session); since that
      # session no longer matches the invoice it is expired, and only then a
      # new attempt is opened for the new amount.
      it 'recovers the pending attempt before renewing it when the amount changed meanwhile' do
        invoice.update_columns(amount: 60)
        stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
          .then.to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                          body: { id: 'cs_newer', object: 'checkout.session',
                                  url: 'https://checkout.stripe.com/c/pay/cs_newer' }.to_json)
        retrieve_as('cs_new', status: 'open', url: 'https://checkout.stripe.com/c/pay/cs_new')
        expire_stub = stub_request(:post, "#{sessions_url}/cs_new/expire")
          .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                     body: { id: 'cs_new', object: 'checkout.session', status: 'expired' }.to_json)

        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_newer'
        expect(a_request(:post, sessions_url).with { |req|
          req.headers['Idempotency-Key'] == key(2) &&
            Rack::Utils.parse_nested_query(req.body).dig('line_items', '0', 'price_data', 'unit_amount') == '5333'
        }).to have_been_made.twice
        expect(expire_stub).to have_been_requested.once
        expect(a_request(:post, sessions_url).with { |req|
          req.headers['Idempotency-Key'] == key(3) &&
            Rack::Utils.parse_nested_query(req.body).dig('line_items', '0', 'price_data', 'unit_amount') == '6000'
        }).to have_been_made.once
        expect(invoice.reload.response).to include(checkout_session_id: 'cs_newer', checkout_attempt: 3,
                                                   checkout_amount_cents: 6000)
      end

      # Scout consultation mt5-2, follow-up 1: the whole create payload is
      # frozen with the attempt, not just key/amount/currency.
      it 'retries with the original payload even if the customer email changed meanwhile' do
        allow_any_instance_of(Invoice).to receive(:email).and_return('changed@example.com')
        stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
        retrieve_as('cs_new', status: 'open', url: 'https://checkout.stripe.com/c/pay/cs_new')
        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'

        bodies = WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                   .select { |sig| sig.method == :post && sig.uri.path == '/v1/checkout/sessions' }
                   .select { |sig| sig.headers['Idempotency-Key'] == key(2) }
                   .map { |sig| Rack::Utils.parse_nested_query(sig.body) }
        expect(creates_with(2)).to have_been_made.twice
        expect(bodies.uniq.size).to be == 1
        expect(bodies.first['customer_email']).not_to be == 'changed@example.com'
        expect(creates_with(3)).not_to have_been_made
      end

      it 'keeps the attempt creating on an idempotency conflict instead of rejecting it' do
        stub_request(:post, sessions_url)
          .to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                     body: { error: { type: 'idempotency_error', message: 'Keys for idempotent requests can only be used with the same parameters' } }.to_json)
        expect(invoice.invoice_send).to be false
        expect(invoice.reload.response).to include(checkout_attempt: 2, checkout_status: 'creating')
        expect(creates_with(3)).not_to have_been_made
      end

      it 'keeps the same key across a 5xx answer' do
        stub_request(:post, sessions_url)
          .to_return(status: 500, headers: { 'Content-Type' => 'application/json' },
                     body: { error: { type: 'api_error', message: 'boom' } }.to_json)
        expect(invoice.invoice_send).to be false
        expect(invoice.reload.response).to include(checkout_attempt: 2, checkout_status: 'creating')
      end

      it 'opens a new attempt only after a definitive 4xx rejection of the create' do
        stub_request(:post, sessions_url)
          .to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                     body: { error: { type: 'invalid_request_error', message: 'bad' } }.to_json)
        expect(invoice.invoice_send).to be false
        expect(invoice.reload.response).to include(checkout_attempt: 2, checkout_status: 'rejected')
        stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
        expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'
        expect(creates_with(3)).to have_been_made.once
      end
    end
  end

  # Scout consultation mt5-2, follow-up 2: editing checkout_status alone does
  # not unblock a session the current credentials cannot retrieve.
  describe 'Invoice#reconcile_checkout!' do
    let(:sessions_url) { "#{StripeHelpers::STRIPE_API}/checkout/sessions" }

    before do
      invoice.update(response: { checkout_session_id: 'cs_lost', checkout_attempt: 1, checkout_status: 'processing',
                                 checkout_idempotency_key: "test-invoice-#{invoice.id}-attempt-1" })
      stub_request(:get, "#{sessions_url}/cs_lost")
        .to_return(status: 404, headers: { 'Content-Type' => 'application/json' },
                   body: { error: { type: 'invalid_request_error', message: 'No such checkout.session' } }.to_json)
    end

    it 'waits while the session is unreachable, even after only editing the status' do
      invoice.update!(response: invoice.response.merge(checkout_status: 'failed'))
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
    end

    it 'records a confirmed failure and then allows exactly one new attempt' do
      invoice.reconcile_checkout!(outcome: 'failed', note: 'boleto expired unpaid in old account')
      expect(invoice.reload.response).to include(checkout_session_id: nil, checkout_status: 'failed',
                                                 checkout_previous_session_id: 'cs_lost')
      expect(invoice.response[:checkout_reconciled]).to include(outcome: 'failed', session_id: 'cs_lost',
                                                                previous_status: 'processing')
      stub_stripe_checkout_session_create(id: 'cs_new', url: 'https://checkout.stripe.com/c/pay/cs_new')
      expect(invoice.invoice_send).to be == 'https://checkout.stripe.com/c/pay/cs_new'
      expect(a_request(:post, sessions_url).with(headers: { 'Idempotency-Key' => "test-invoice-#{invoice.id}-attempt-2" })).to have_been_made.once
    end

    it 'marks the invoice paid for a confirmed payment and never charges again' do
      invoice.update_columns(state: Invoice.states[:to_paid])
      invoice.reconcile_checkout!(outcome: :paid, note: 'paid in old account, pi_123')
      expect(invoice.reload.state).to be == 'paid'
      create_stub = stub_stripe_checkout_session_create
      expect(invoice.invoice_send).to be false
      expect(create_stub).not_to have_been_requested
    end

    it 'requires a known outcome and a note' do
      expect { invoice.reconcile_checkout!(outcome: 'open', note: 'x') }.to raise_error(ArgumentError)
      expect { invoice.reconcile_checkout!(outcome: 'failed', note: '') }.to raise_error(ArgumentError)
      expect(invoice.reload.response[:checkout_session_id]).to be == 'cs_lost'
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
