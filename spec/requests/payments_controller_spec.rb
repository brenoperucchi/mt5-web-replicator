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

    it 'marks the invoice denied when the session expires' do
      post_event('checkout.session.expired', session_object(invoice, payment_status: 'unpaid', status: 'expired'))
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'denied'
    end

    it 'marks the invoice refunded on charge.refunded' do
      invoice.update(response: { checkout_session_id: 'cs_test_1', payment_intent_id: 'pi_test_1' })
      invoice.update_columns(state: Invoice.states[:paid])
      post_event('charge.refunded', { id: 'ch_test_1', object: 'charge', payment_intent: 'pi_test_1', metadata: {} })
      expect(response).to have_http_status 200
      expect(invoice.reload.state).to be == 'refunded'
    end

    it 'returns 400 when the event references an unknown invoice' do
      post_event('checkout.session.completed', session_object(invoice, client_reference_id: '0', metadata: { invoice_id: '0' }))
      expect(response).to have_http_status 400
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

    it 'renders the cancel page without calling Stripe' do
      get "/payments/#{invoice.id}/return/cancel"
      expect(response).to have_http_status 200
      expect(response.body).to include('Payment not completed')
    end
  end
end
