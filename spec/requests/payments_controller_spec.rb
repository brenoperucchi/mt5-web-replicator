require 'rails_helper'

RSpec.describe 'Payments Controller', type: :request do
  before(:context) do
    unfreeze_time
    travel_to Date.parse("2023-06-01")
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @payment = @store.payments.first
    @user_customer = create(:user, :customer, store: @store)
    @customer = create(:customer, :customer, user: @user_customer)
  end

  let(:invoice) do
    Invoice.create!(name: "payments-spec-#{SecureRandom.hex(3)}", store: @store, payment: @payment,
                    invoiceable: @customer, amount: 49.9, state: :to_paid)
  end

  def post_event(type, object, secret: 'whsec_test')
    payload = stripe_event_payload(type, object)
    post "/payments/webhook/#{@payment.id}", params: payload,
      headers: { 'Content-Type' => 'application/json', 'Stripe-Signature' => stripe_signature_header(payload, secret: secret) }
  end

  def session_object(invoice, **attrs)
    { id: 'cs_test_1', object: 'checkout.session', payment_status: 'paid', status: 'complete',
      payment_intent: 'pi_test_1', client_reference_id: invoice.id.to_s,
      metadata: { invoice_id: invoice.id.to_s } }.merge(attrs)
  end

  describe 'POST /payments/webhook/:payment_id' do
    it 'marks the invoice paid on a validly signed checkout.session.completed' do
      expect {
        post_event('checkout.session.completed', session_object(invoice))
        invoice.reload
      }.to change(invoice, :state).from('to_paid').to('paid')
      expect(response).to have_http_status 200
      expect(invoice.response[:payment_intent_id]).to be == 'pi_test_1'
      expect(invoice.loggings.last.state).to be == 'PAID'
    end

    it 'rejects an invalid signature with 400 and leaves the invoice untouched' do
      post_event('checkout.session.completed', session_object(invoice), secret: 'whsec_wrong')
      expect(response).to have_http_status 400
      expect(invoice.reload.state).to be == 'to_paid'
      expect(Logging.last.state).to be == 'INVALID SIGNATURE'
    end

    it 'keeps the invoice payable (to_paid) when the session expires' do
      invoice.update(response: { checkout_session_id: 'cs_test_1' })
      post_event('checkout.session.expired', session_object(invoice, payment_status: 'unpaid', status: 'expired'))
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'to_paid'
    end

    it 'rejects events signed with an empty key when no webhook secret is configured' do
      unconfigured = Payment.create!(payment_method: @payment.payment_method, store: @store, webhook_token: nil)
      inv = Invoice.create!(name: "payments-spec-#{SecureRandom.hex(3)}", store: @store, payment: unconfigured,
                            invoiceable: @customer, amount: 49.9, state: :to_paid)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return(nil)
      payload = stripe_event_payload('checkout.session.completed', session_object(inv))
      post "/payments/webhook/#{unconfigured.id}", params: payload,
        headers: { 'Content-Type' => 'application/json', 'Stripe-Signature' => stripe_signature_header(payload, secret: '') }
      expect(response).to have_http_status 400
      expect(Logging.last.state).to be == 'INVALID SIGNATURE'
      expect(inv.reload.state).to be == 'to_paid'
    end

    context 'monotonic state transitions' do
      it 'keeps a paid invoice paid when another session of it expires' do
        invoice.update(response: { checkout_session_id: 'cs_test_1', payment_intent_id: 'pi_test_1' })
        invoice.update_columns(state: Invoice.states[:paid])
        post_event('checkout.session.expired', session_object(invoice, id: 'cs_old', payment_status: 'unpaid', status: 'expired'))
        expect(response).to have_http_status 200
        expect(invoice.reload.state).to be == 'paid'
        expect(invoice.response[:checkout_session_id]).to be == 'cs_test_1'
      end

      it 'does not deny the invoice on async_payment_failed of an older session' do
        invoice.update(response: { checkout_session_id: 'cs_new' })
        post_event('checkout.session.async_payment_failed', session_object(invoice, id: 'cs_old', payment_status: 'unpaid'))
        expect(invoice.reload.state).to be == 'to_paid'
        expect(invoice.response[:checkout_session_id]).to be == 'cs_new'
      end

      it 'denies the invoice on async_payment_failed of the current session' do
        invoice.update(response: { checkout_session_id: 'cs_test_1' })
        post_event('checkout.session.async_payment_failed', session_object(invoice, payment_status: 'unpaid'))
        expect(invoice.reload.state).to be == 'denied'
      end

      it 'does not undo a refund when a delayed completed event arrives' do
        invoice.update(response: { checkout_session_id: 'cs_test_1', payment_intent_id: 'pi_test_1' })
        invoice.update_columns(state: Invoice.states[:refunded])
        post_event('checkout.session.completed', session_object(invoice))
        expect(response).to have_http_status 200
        expect(invoice.reload.state).to be == 'refunded'
      end

      it 'is idempotent for duplicated events' do
        invoice.update(response: { checkout_session_id: 'cs_test_1' })
        2.times { post_event('checkout.session.completed', session_object(invoice)) }
        expect(response).to have_http_status 200
        expect(invoice.reload.state).to be == 'paid'
      end
    end

    it 'only logs a partial refund (charge.refunded with refunded=false)' do
      invoice.update(response: { checkout_session_id: 'cs_test_1', payment_intent_id: 'pi_test_1' })
      invoice.update_columns(state: Invoice.states[:paid])
      post_event('charge.refunded', { id: 'ch_test_1', object: 'charge', payment_intent: 'pi_test_1',
                                      refunded: false, amount_refunded: 100, metadata: {} })
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'paid'
    end

    it 'marks the invoice refunded on charge.refunded' do
      invoice.update(response: { checkout_session_id: 'cs_test_1', payment_intent_id: 'pi_test_1' })
      invoice.update_columns(state: Invoice.states[:paid])
      post_event('charge.refunded', { id: 'ch_test_1', object: 'charge', payment_intent: 'pi_test_1', refunded: true, metadata: {} })
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'refunded'
    end

    it 'acknowledges a signed event for an unknown invoice so Stripe stops retrying' do
      post_event('checkout.session.completed', session_object(invoice, client_reference_id: '0', metadata: { invoice_id: '0' }))
      expect(response).to have_http_status 200
      expect(Logging.last.state).to be == 'INVOICE NOTFIND'
    end

    # mt5-2 rev-2 N1: several stores' Stripe payments with blank tokens share
    # the ENV secret, so only one endpoint can be registered for all of them.
    context 'with payments sharing the ENV webhook secret' do
      let(:store_b) { create(:store, :store2, plan_id: @plan1.id) }
      let(:shared_a) { Payment.create!(payment_method: @payment.payment_method, store: @store) }
      let(:shared_b) { Payment.create!(payment_method: @payment.payment_method, store: store_b) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('STRIPE_WEBHOOK_SECRET').and_return('whsec_env')
      end

      def post_to(payment, type, object, secret:)
        payload = stripe_event_payload(type, object)
        post "/payments/webhook/#{payment.id}", params: payload,
          headers: { 'Content-Type' => 'application/json', 'Stripe-Signature' => stripe_signature_header(payload, secret: secret) }
      end

      it "processes another store's invoice when both resolve to the same secret" do
        inv_b = Invoice.create!(name: "payments-spec-#{SecureRandom.hex(3)}", store: store_b, payment: shared_b,
                                invoiceable: @customer, amount: 49.9, state: :to_paid)
        post_to(shared_a, 'checkout.session.completed', session_object(inv_b), secret: 'whsec_env')
        expect(response).to have_http_status 200
        expect(inv_b.reload.state).to be == 'paid'
      end

      it 'matches a refund of another store invoice by payment intent' do
        inv_b = Invoice.create!(name: "payments-spec-#{SecureRandom.hex(3)}", store: store_b, payment: shared_b,
                                invoiceable: @customer, amount: 49.9, state: :paid,
                                response: { checkout_session_id: 'cs_b', payment_intent_id: 'pi_b' })
        post_to(shared_a, 'charge.refunded', { id: 'ch_b', object: 'charge', payment_intent: 'pi_b', refunded: true, metadata: {} },
                secret: 'whsec_env')
        expect(inv_b.reload.state).to be == 'refunded'
      end

      it 'does not let a store with its own webhook secret process another store invoice' do
        inv_b = Invoice.create!(name: "payments-spec-#{SecureRandom.hex(3)}", store: store_b, payment: shared_b,
                                invoiceable: @customer, amount: 49.9, state: :to_paid)
        # @payment has its own token (whsec_test), distinct from the ENV secret used by shared_b.
        post_event('checkout.session.completed', session_object(inv_b))
        expect(response).to have_http_status 200
        expect(Logging.last.state).to be == 'INVOICE NOTFIND'
        expect(inv_b.reload.state).to be == 'to_paid'
      end
    end

    it 'returns 400 for a payment whose provider no longer exists' do
      legacy = PaymentMethod.create!(name: 'Legacy', handle: 'mercado_pago')
      legacy_payment = Payment.create!(payment_method: legacy, store: @store)
      post "/payments/webhook/#{legacy_payment.id}", params: '{}', headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status 400
    end
  end

  describe 'GET /payments/:invoice_id/return/:kind' do
    it 'syncs the checkout session and shows the confirmation' do
      stub = stub_stripe_checkout_session_retrieve(session_object(invoice))
      get "/payments/#{invoice.id}/return/success", params: { session_id: 'cs_test_1' }
      expect(stub).to have_been_requested
      expect(response).to have_http_status 200
      expect(response.body).to include('Payment confirmed')
      expect(invoice.reload.state).to be == 'paid'
    end

    it 'does not mark the invoice paid for a session belonging to another invoice' do
      stub_stripe_checkout_session_retrieve(session_object(invoice, client_reference_id: '0', metadata: { invoice_id: '0' }))
      get "/payments/#{invoice.id}/return/success", params: { session_id: 'cs_test_1' }
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'to_paid'
    end

    it 'does not undo a refund when the customer returns to the success page' do
      invoice.update(response: { checkout_session_id: 'cs_test_1', payment_intent_id: 'pi_test_1' })
      invoice.update_columns(state: Invoice.states[:refunded])
      stub_stripe_checkout_session_retrieve(session_object(invoice))
      get "/payments/#{invoice.id}/return/success", params: { session_id: 'cs_test_1' }
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'refunded'
    end

    it 'renders the cancel page without calling Stripe' do
      get "/payments/#{invoice.id}/return/cancel"
      expect(response).to have_http_status 200
      expect(response.body).to include('Payment not completed')
    end
  end
end
