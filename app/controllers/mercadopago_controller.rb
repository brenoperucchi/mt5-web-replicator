require 'mercadopago'
class MercadopagoController < ApplicationController
  layout 'stripe'
  skip_before_action :verify_authenticity_token, only: [:webhook, :mercadopago, :process_payment, :back_urls]

  def webhook
    # render :nothing => false, :status => 200, :content_type => 'text/html'
    store = Store.find(params[:store_id])
    payment = Payment.find_by(id: params[:payment_id])
    logging = Logging.create(content:params, state: "WEBHOOK PENDING", loggerable:store)
    payment_method = payment.payment_method.provider(payment)
    payment_method.check_payment(params)
    response = payment_method.response
    invoice = payment_method.invoice
    if invoice && payment && response
      response_status = response.dig(:response, "status")
      if invoice and invoice.try(:pending?)
        invoice.payment_status(response_status)
        logging.update(content:params.merge(response:response), state: response_status, changeset: invoice.try(:versions).try(:last).try(:changeset), loggerable:invoice)
      end
      head 201
    else
      logging.update(state: 'INVOICE NOTFIND', content: params) if invoice.nil?
      logging.update(state: 'PAYMENT NOTFIND', content: params) if invoice.nil?
      head 400
    end
  end

  def back_urls
    @params = {payment_id: params[:payment_id], status: params[:status], external_reference: params[:external_reference], merchant_order_id: params[:merchant_order_id]}
    @invoice = Invoice.find(params[:invoice_id])
    respond_to do |wants|
      wants.html { render :back_urls, layout: 'modernize'}
    end
  end

  def finish
    @invoice = Invoice.find(params[:invoice_id])
    if @invoice.response.dig(:payment, :status) == 'approved'
      @to_render = :success
    else
      @to_render = :failure
    end
    respond_to do |wants|
      wants.html { render :finish}
    end

  end


  def process_payment
    @invoice = Invoice.find(params[:invoice_id])

    payment_data = {
      transaction_amount: params[:transaction_amount].to_f,
      token: params[:token],
      description: params[:description],
      installments: params[:installments].to_i,
      payment_method_id: params[:payment_method_id],
      payer: {
        email: params[:payer][:email],
        identification: {
          type: params[:payer][:identification][:type],
          number: params[:payer][:identification][:number]
        },
        first_name: @invoice.invoiceable.name
      }
    }

    response = @invoice.payment_method.payment(payment_data)
    puts response

    # @invoice.response["payment"].to_json
    # puts @invoice.response["payment"]

    # redirect_to finish_mercadopago_path(@invoice) 
  end

end