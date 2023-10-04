require 'mercadopago'
class MercadopagoController < ApplicationController
  layout 'stripe'
  skip_before_action :verify_authenticity_token, only: [:webhook, :mercadopago, :process_payment, :back_urls]

  def webhook
    # render :nothing => false, :status => 200, :content_type => 'text/html'
    store = Store.find(params[:id])
    payment = Payment.find_by(id: params[:payment_id])
    logging = Logging.create(content:params, state: "WEBHOOK PENDING", loggerable:store)
    if payment
      sdk = Mercadopago::SDK.new(payment.api_token)
      if params[:topic] == "merchant_order"       #ipn payment
        responde_id = params.dig(:resource).scan(/\d+/).last
        response = sdk.merchant_order.get(responde_id)
        response_status = response.dig(:response, "status")
        invoice = Invoice.find_by(id: response.dig(:response, "external_reference"))

        if invoice and invoice.pending?
          invoice.update(state: response_status)
            invoice.loggings.create(content:params.merge(response:response), state: response_status, changeset: invoice.try(:versions).try(:last).try(:changeset))
          # invoice.update(state: 'open') if response_status == "pending"
        end
      else                                        #webhook payment
        responde_id = params.dig(:data, :id)
        response = sdk.payment.get(responde_id)
        response_status = response.dig(:response, "status")
        invoice = Invoice.find_by(id: response.dig(:response, "external_reference"))     
          if invoice and invoice.pending?
            invoice.update(state: 'paid') if response_status == "approved"
            invoice.update(state: 'reject') if response_status == "reject"
            logging.update(content:params.merge(response: response), state: response_status, changeset: invoice.try(:versions).try(:last).try(:changeset))
          end
      end

      if invoice.nil?
        logging.update(state:"INVOICE NOTFIND", content: params)
        head 201
        return
      else
        head 201
        return 
      end
    end

    logging.update(state:"PAYMENT NOTFIND", content: params)    
    head 400
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
    if @invoice.response.dig(:payment, :status) == "approved"
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