class PaymentsController < ApplicationController
  layout 'modernize'
  skip_before_action :verify_authenticity_token, only: [:webhook]

  RETURN_KINDS = %w[success failure pending cancel].freeze

  # POST /payments/webhook/:payment_id
  def webhook
    payment = Payment.find_by(id: params[:payment_id])
    logging = Logging.create(content: request.raw_post, state: "WEBHOOK PENDING", loggerable: payment.try(:store))

    provider = payment.try(:payment_method).try(:provider, payment)
    if provider.nil?
      logging.update(state: 'PAYMENT NOTFIND')
      return head :bad_request
    end

    begin
      invoice = provider.handle_webhook(request)
    rescue PaymentMethod::SignatureError => e
      logging.update(state: 'INVALID SIGNATURE', error_message: e.message)
      return head :bad_request
    end

    if invoice
      invoice.reload
      logging.update(state: invoice.state.upcase, loggerable: invoice,
                     changeset: invoice.try(:versions).try(:last).try(:changeset))
      head :ok
    else
      # Signed but irrelevant (unhandled event type or unknown invoice): ack it,
      # otherwise the provider keeps retrying and may disable the endpoint.
      logging.update(state: 'INVOICE NOTFIND')
      head :ok
    end
  end

  # GET /payments/:invoice_id/return/:kind
  def checkout_return
    @invoice = Invoice.find(params[:invoice_id])
    @kind = RETURN_KINDS.include?(params[:kind]) ? params[:kind] : 'pending'

    provider = @invoice.payment_method
    begin
      provider&.sync(@invoice, params)
    rescue StandardError => e
      Rails.logger.error("PaymentsController#return - sync failed for Invoice##{@invoice.id}: #{e.message}")
    end
    @invoice.reload

    render :checkout_return
  end
end
