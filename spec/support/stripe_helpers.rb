require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

module StripeHelpers
  STRIPE_API = 'https://api.stripe.com/v1'.freeze

  def stub_stripe_checkout_session_create(id: 'cs_test_123', url: 'https://checkout.stripe.com/c/pay/cs_test_123')
    stub_request(:post, "#{STRIPE_API}/checkout/sessions")
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { id: id, object: 'checkout.session', url: url }.to_json)
  end

  def stub_stripe_checkout_session_retrieve(session)
    stub_request(:get, "#{STRIPE_API}/checkout/sessions/#{session[:id]}")
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { object: 'checkout.session' }.merge(session).to_json)
  end

  def stripe_event_payload(type, object)
    { id: "evt_#{SecureRandom.hex(6)}", object: 'event', type: type, data: { object: object } }.to_json
  end

  def stripe_signature_header(payload, secret: 'whsec_test', timestamp: Time.now)
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    "t=#{timestamp.to_i},v1=#{signature}"
  end
end

RSpec.configure do |config|
  config.include StripeHelpers
end
