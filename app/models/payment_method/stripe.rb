class PaymentMethod::Stripe


  PAID_EVENTS    = %w[checkout.session.completed checkout.session.async_payment_succeeded].freeze
  # An expired session changes nothing: the invoice stays payable (a new
  # session is created on the next checkout). A failed async payment denies it,
  # but only when it is the invoice's current session.
  DENIED_EVENTS  = %w[checkout.session.async_payment_failed].freeze
  EXPIRED_EVENTS = %w[checkout.session.expired].freeze
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

  # Returns a hosted Checkout URL for the invoice, or nil when it must not or
  # could not be charged. Serialized per invoice with a row lock:
  # - paid/refunded invoices are never charged again;
  # - a still-open session is reused instead of creating a second one;
  # - new sessions use an idempotency key stable per attempt, so a retried
  #   request (timeout, double click) cannot create duplicate sessions.
  def checkout(invoice)
    invoice.with_lock do
      if invoice.paid? || invoice.refunded?
        Rails.logger.info("Stripe: Invoice##{invoice.id} is #{invoice.state}; checkout refused")
        next nil
      end

      unit_amount = (invoice.amount.to_d * 100).round.to_i
      if unit_amount < 1
        Rails.logger.warn("Stripe: Invoice##{invoice.id} amount #{invoice.amount.inspect} is below the minimum; no session created")
        next nil
      end

      url = open_session_url(invoice)
      next url if url
      next nil if invoice.paid?

      create_session(invoice, unit_amount)
    end
  end

  # Verifies the Stripe signature and applies the event. Returns the updated
  # Invoice, or nil when the event does not reference a known invoice.
  def handle_webhook(request)
    payload = request.raw_post
    signature = request.headers['Stripe-Signature']
    secret = webhook_secret
    # An empty secret is a known HMAC key: anyone could forge events with it.
    raise PaymentMethod::SignatureError, 'webhook secret not configured' if secret.blank?

    begin
      event = ::Stripe::Webhook.construct_event(payload, signature, secret)
    rescue ::Stripe::SignatureVerificationError, JSON::ParserError => e
      raise PaymentMethod::SignatureError, e.message
    end

    object = event.data.object
    case event.type
    when *PAID_EVENTS, *DENIED_EVENTS, *EXPIRED_EVENTS
      invoice = invoice_from_session(object)
      apply_session(invoice, object, event.type) if invoice
      invoice
    when *REFUND_EVENTS
      invoice = invoice_from_charge(object)
      if invoice
        if object.try(:refunded) == true
          invoice.payment_status(:refunded)
        else
          Rails.logger.info("Stripe: partial refund on Invoice##{invoice.id} " \
                            "(amount_refunded=#{object.try(:amount_refunded)}); state unchanged")
        end
      end
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

  # Only the invoice's current session may move it to a negative state or
  # replace the stored session id. A paid session is honored even if it is an
  # older one (the customer may have paid a still-open older link); the
  # transition rules in Invoice#payment_status keep refunded invoices refunded.
  def apply_session(invoice, session, event_type = nil)
    current_id = invoice.response[:checkout_session_id]
    current = current_id.blank? || current_id == session.id
    paid = %w[paid no_payment_required].include?(session.payment_status)

    if current || paid
      attrs = { payment_intent_id: session.try(:payment_intent).presence || invoice.response[:payment_intent_id] }
      attrs[:checkout_session_id] = session.id if current
      invoice.update(response: invoice.response.merge(attrs).compact)
    end

    if paid
      invoice.payment_status(:paid)
    elsif current && DENIED_EVENTS.include?(event_type)
      invoice.payment_status(:denied)
    end
  end

  def open_session_url(invoice)
    session_id = invoice.response[:checkout_session_id]
    return nil if session_id.blank?

    session = ::Stripe::Checkout::Session.retrieve(session_id, { api_key: api_key })
    # A completed session whose webhook has not arrived yet: record it rather
    # than opening a second payment for the same invoice.
    apply_session(invoice, session) if session.status == 'complete'
    session.url.presence if session.status == 'open'
  rescue ::Stripe::StripeError => e
    Rails.logger.warn("Stripe: could not retrieve #{session_id} for Invoice##{invoice.id}: #{e.message}")
    nil
  end

  # The attempt number only moves forward when a new session is needed
  # (a previous one exists but is no longer open, or Stripe rejected the
  # request); a retry after a network failure reuses the same key.
  def create_session(invoice, unit_amount)
    attempt = [invoice.response[:checkout_attempt].to_i, 1].max
    attempt += 1 if invoice.response[:checkout_session_id].present?
    invoice.update_column(:response, invoice.response.merge(checkout_attempt: attempt))

    params = {
      mode: 'payment',
      client_reference_id: invoice.id.to_s,
      metadata: { invoice_id: invoice.id },
      payment_intent_data: { metadata: { invoice_id: invoice.id } },
      line_items: [{
        quantity: 1,
        price_data: {
          currency: currency,
          unit_amount: unit_amount,
          product_data: { name: title(invoice) },
        },
      }],
      success_url: "#{invoice.back_urls(:success)}?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: invoice.back_urls(:cancel),
    }
    email = customer_email(invoice)
    params[:customer_email] = email if email.present?

    session = ::Stripe::Checkout::Session.create(
      params, { api_key: api_key, idempotency_key: "invoice-#{invoice.id}-attempt-#{attempt}" }
    )
    invoice.update(response: invoice.response.merge(checkout_session_id: session.id))
    session.url
  rescue ::Stripe::StripeError => e
    Rails.logger.error("Stripe: checkout failed for Invoice##{invoice.id}: #{e.class}: #{e.message}")
    # Stripe replays the stored result of a key, so a rejected request needs a
    # fresh key next time; a connection error may be retried with the same one.
    unless e.is_a?(::Stripe::APIConnectionError)
      invoice.update_column(:response, invoice.response.merge(checkout_attempt: attempt + 1))
    end
    nil
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
