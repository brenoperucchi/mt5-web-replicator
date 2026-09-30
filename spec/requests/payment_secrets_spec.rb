require 'rails_helper'

# Payment#api_token / #webhook_token are Stripe secrets: the admin and control
# dashboards must never render them, and a blank form submission must keep them.
RSpec.describe 'Payment secrets in admin/control dashboards', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:token) { 'sk_test_abcdef123456' }
  let(:webhook) { 'whsec_zyxwvu987654' }
  let(:plan) { create(:plan, :plan1) }
  let(:store) { create(:store, plan_id: plan.id) }
  let(:payment) { store.payments.first.tap { |p| p.update!(api_token: token, webhook_token: webhook) } }

  {
    'admin'   => { role: 'administrator', role_control: 'admin' },
    'control' => { role: 'customer',      role_control: 'admin' },
  }.each do |namespace, roles|
    context "/#{namespace}/payments" do
      before do
        user = create(:user, :admin, store: store)
        create(:customer, :admin, user: user, customer_plan_ids: store.customer_plan_ids, **roles)
        sign_in user
      end

      it 'masks the tokens on the show page' do
        get "/#{namespace}/payments/#{payment.id}"
        expect(response).to have_http_status 200
        expect(response.body).not_to include(token)
        expect(response.body).not_to include(webhook)
        expect(response.body).to include('••••3456')
        expect(response.body).to include('••••7654')
      end

      it 'masks the token on the index page' do
        payment
        get "/#{namespace}/payments"
        expect(response).to have_http_status 200
        expect(response.body).not_to include(token)
        expect(response.body).to include('••••3456')
      end

      it 'renders an empty password input on the edit form' do
        get "/#{namespace}/payments/#{payment.id}/edit"
        expect(response).to have_http_status 200
        expect(response.body).not_to include(token)
        expect(response.body).to match(/<input[^>]*type="password"[^>]*name="payment\[api_token\]"|<input[^>]*name="payment\[api_token\]"[^>]*type="password"/)
      end

      it 'keeps the existing secrets when the fields are submitted blank' do
        patch "/#{namespace}/payments/#{payment.id}", params: { payment: { api_token: '', webhook_token: '', min_amount: 7 } }
        payment.reload
        expect(payment.api_token).to eq token
        expect(payment.webhook_token).to eq webhook
        expect(payment.min_amount.to_i).to eq 7
      end

      it 'replaces the secret when a new value is submitted' do
        patch "/#{namespace}/payments/#{payment.id}", params: { payment: { api_token: 'sk_test_new999', webhook_token: '' } }
        payment.reload
        expect(payment.api_token).to eq 'sk_test_new999'
        expect(payment.webhook_token).to eq webhook
      end
    end
  end
end
