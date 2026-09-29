require 'rails_helper'

RSpec.describe 'Panel::InvoicesController', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:plan) { create(:plan, :plan1) }
  let(:store) { create(:store, plan_id: plan.id) }
  let(:payment) { store.payments.first }
  let(:owner) { create(:customer, :customer, user: create(:user, :customer, store: store)) }
  let(:other) { create(:customer, :customer2, user: create(:user, email: 'other@store.com', password: '123123', store: store)) }

  def invoice_for(customer)
    Invoice.create!(name: 'INV-2026-09', state: :to_paid, amount: 10, store: store, payment: payment,
                    invoiceable: customer, response: {})
  end

  describe 'GET /panel/invoices/:id/invoice_send' do
    it "does not start checkout for another customer's invoice" do
      foreign = invoice_for(other)
      sign_in owner.user

      get "/panel/invoices/#{foreign.id}/invoice_send"

      expect(response).to have_http_status 404
      expect(a_request(:any, /api\.stripe\.com/)).not_to have_been_made
      expect(foreign.reload.payment_link).to be_blank
    end
  end

  # mt5-2 rev-2 N4
  describe 'GET /panel/invoices/:id/item_conciliated/:item_id' do
    it "does not show another customer's invoice item" do
      foreign = invoice_for(other)
      item = foreign.items.create!(handle: 'month_slave', amount: 10, description: 'x')
      own = invoice_for(owner)
      sign_in owner.user

      get "/panel/invoices/#{foreign.id}/item_conciliated/#{item.id}"
      expect(response).to have_http_status 404

      # Nor through the signed-in customer's own invoice id.
      sign_in owner.user
      get "/panel/invoices/#{own.id}/item_conciliated/#{item.id}"
      expect(response).to have_http_status 404
    end
  end
end
