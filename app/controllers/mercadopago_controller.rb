require 'mercadopago'
class MercadopagoController < ApplicationController
  layout 'stripe'
  skip_before_action :verify_authenticity_token, only: [:webhook, :mercadopago]

  def webhook
    # render :nothing => false, :status => 200, :content_type => 'text/html'
    store = Store.find(params[:id])
    payment = Payment.find_by(id: params[:payment_id])
    if payment
      sdk = Mercadopago::SDK.new(payment.api_token)
      if params[:topic] == "merchant_order"       #ipn payment
        responde_id = params.dig(:resource).scan(/\d+/).last
        response = sdk.merchant_order.get(responde_id)
        response_status = response.dig(:response, "status")
        invoice = Invoice.find_by(id: response.dig(:response, "external_reference"))

        if invoice and invoice.pending?
          invoice.update(state: 'paid') if response_status == "approved"
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
            invoice.loggings.create(content:params.merge(response: response), state: response_status, changeset: invoice.try(:versions).try(:last).try(:changeset))
            # invoice.update(state: 'open') if response_status == "pending"
          end
      end

      if invoice.nil?
        store.loggings.create(state:"INVOICE NOTFIND", content: params)
        head 201
        return
      else
        head 201
        return 
      end
    end

    store.loggings.create(state:"PAYMENT NOTFIND", content: params)    
    head 400
  end

end