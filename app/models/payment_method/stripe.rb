class PaymentMethod::Stripe


  PAID_EVENTS    = %w[checkout.session.completed checkout.session.async_payment_succeeded].freeze
  DENIED_EVENTS  = %w[checkout.session.async_payment_failed checkout.session.expired].freeze
  REFUND_EVENTS  = %w[charge.refunded].freeze

  attr_reader :payment

  def initialize(payment)
    @payment = payment
  end

  def api_key
    payment.try(:api_token).presence || ENV['STRIPE_SECRET_KEY']
  end

  def webhook_secret
    payment.try(:webhook_token).presence || ENV['STRIPE_WEBHOOK_SECRET']
  end

  def currency
    ENV.fetch('PAYMENT_CURRENCY', 'usd').downcase
  end

  # Creates a hosted Checkout Session and returns its URL.
  def checkout(invoice)
    params = {
      mode: 'payment',
      client_reference_id: invoice.id.to_s,
      metadata: { invoice_id: invoice.id },
      payment_intent_data: { metadata: { invoice_id: invoice.id } },
      line_items: [{
        quantity: 1,
        price_data: {
          currency: currency,
          unit_amount: (invoice.amount.to_d * 100).round.to_i,
          product_data: { name: title(invoice) },
        },
      }],
      success_url: "#{invoice.back_urls(:success)}?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: invoice.back_urls(:cancel),
    }
    email = customer_email(invoice)
    params[:customer_email] = email if email.present?

    session = ::Stripe::Checkout::Session.create(params, { api_key: api_key })
    invoice.update(response: invoice.response.merge(checkout_session_id: session.id))
    session.url
  end

  # Verifies the Stripe signature and applies the event. Returns the updated
  # Invoice, or nil when the event does not reference a known invoice.
  def handle_webhook(request)
    payload = request.raw_post
    signature = request.headers['Stripe-Signature']
    begin
      event = ::Stripe::Webhook.construct_event(payload, signature, webhook_secret.to_s)
    rescue ::Stripe::SignatureVerificationError, JSON::ParserError => e
      raise PaymentMethod::SignatureError, e.message
    end

    object = event.data.object
    case event.type
    when *PAID_EVENTS, *DENIED_EVENTS
      invoice = invoice_from_session(object)
      apply_session(invoice, object, event.type) if invoice
      invoice
    when *REFUND_EVENTS
      invoice = invoice_from_charge(object)
      invoice&.payment_status(:refunded)
      invoice
    end
  end

  # Called when the customer returns from Checkout (?session_id=...).
  def sync(invoice, params)
    session_id = params[:session_id].presence || invoice.response[:checkout_session_id]
    return invoice if session_id.blank?

    session = ::Stripe::Checkout::Session.retrieve(session_id, { api_key: api_key })
    return invoice unless session_invoice_id(session).to_s == invoice.id.to_s

    apply_session(invoice, session)
    invoice
  end

  private

  def apply_session(invoice, session, event_type = nil)
    invoice.update(response: invoice.response.merge(
      checkout_session_id: session.id,
      payment_intent_id: session.try(:payment_intent).presence || invoice.response[:payment_intent_id]
    ).compact)

    if session.payment_status == 'paid' || session.payment_status == 'no_payment_required'
      invoice.payment_status(:paid)
    elsif DENIED_EVENTS.include?(event_type) || session.status == 'expired'
      invoice.payment_status(:denied)
    end
  end

  def invoice_from_session(session)
    Invoice.find_by(id: session_invoice_id(session), payment_id: payment.id)
  end

  def session_invoice_id(session)
    session.try(:metadata).try(:[], :invoice_id).presence || session.try(:client_reference_id)
  end

  def invoice_from_charge(charge)
    invoice_id = charge.try(:metadata).try(:[], :invoice_id).presence
    invoice = Invoice.find_by(id: invoice_id, payment_id: payment.id) if invoice_id
    return invoice if invoice

    intent = charge.try(:payment_intent)
    return nil if intent.blank?
    Invoice.where(payment_id: payment.id)
           .where("response LIKE ?", "%#{Invoice.sanitize_sql_like(intent)}%")
           .find { |inv| inv.response[:payment_intent_id] == intent }
  end

  def customer_email(invoice)
    invoice.email.presence || invoice.invoiceable.try(:email).presence
  end

  def title(invoice)
    if invoice.invoiceable_type == "Customer"
      "Subscription - #{invoice.invoiceable.try(:name)}"
    else
      "Plan - #{invoice.items.first.try(:name) || invoice.name}"
    end
  end

end
