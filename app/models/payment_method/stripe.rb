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
  # could not be charged right now (Invoice#invoice_send then returns false).
  #
  # Each checkout attempt is tracked in invoice.response:
  #   checkout_attempt, checkout_idempotency_key, checkout_amount_cents,
  #   checkout_currency, checkout_session_id and checkout_status, one of
  #   creating   - persisted before calling Stripe; the create may have
  #                succeeded remotely even if its response was lost
  #   open       - session published to the customer
  #   processing - complete/unpaid (async payment still clearing)
  #   failed / expired / rejected / paid - closed
  # The status is per attempt: the invoice's `denied` state is history and
  # never, by itself, allows a new attempt.
  #
  # Decided under the invoice row lock:
  # - paid/refunded invoices are never charged again;
  # - a `creating` attempt is retried with the same key and parameters (Stripe
  #   replays the same session) until it succeeds or is definitively rejected;
  # - an open session is reused while its amount/currency match the invoice,
  #   otherwise it is expired first;
  # - a new attempt starts only when there is none or the current one is
  #   confirmed failed/expired/rejected; anything inconclusive (pending async
  #   payment, lookup/expire error) returns nil and keeps the current attempt.
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

      # Recover a create whose outcome is unknown before deciding anything.
      next nil if invoice.response[:checkout_status] == 'creating' && !perform_create(invoice)

      verdict, url = previous_session(invoice, unit_amount)
      case verdict
      when :reuse then url
      when :new
        start_attempt(invoice, unit_amount)
        perform_create(invoice)
      else nil
      end
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

  STATUS_RANK = { 'creating' => 0, 'open' => 1, 'processing' => 2,
                  'failed' => 3, 'expired' => 3, 'rejected' => 3, 'paid' => 4 }.freeze

  # Only the invoice's current session may change the attempt status or deny
  # the invoice; events of an older session never release a new attempt. A
  # paid session is honored even if it is an older one (the customer may have
  # paid a still-open older link); the transition rules in
  # Invoice#payment_status keep refunded invoices refunded.
  def apply_session(invoice, session, event_type = nil)
    current_id = invoice.response[:checkout_session_id]
    current = current_id.present? && current_id == session.id
    paid = %w[paid no_payment_required].include?(session.payment_status)

    if current || paid
      attrs = { payment_intent_id: session.try(:payment_intent).presence || invoice.response[:payment_intent_id] }
      if current
        status = if paid then 'paid'
                 elsif DENIED_EVENTS.include?(event_type) then 'failed'
                 elsif EXPIRED_EVENTS.include?(event_type) || session.status == 'expired' then 'expired'
                 elsif session.status == 'complete' then 'processing'
                 end
        attrs[:checkout_status] = advance(invoice.response[:checkout_status], status)
      end
      # update! so a failed save raises here instead of leaving dirty
      # attributes that make the row lock in payment_status raise later.
      invoice.update!(response: invoice.response.merge(attrs).compact)
    end

    if paid
      invoice.payment_status(:paid)
    elsif current && DENIED_EVENTS.include?(event_type)
      invoice.payment_status(:denied)
    end
  end

  # Attempt statuses only move forward (a late `completed` cannot reopen a
  # failed attempt as processing).
  def advance(from, to)
    return from if to.nil?
    return to if from.nil?
    STATUS_RANK.fetch(to, 0) > STATUS_RANK.fetch(from, 0) ? to : from
  end

  def set_status(invoice, status)
    invoice.update_column(:response, invoice.response.merge(checkout_status: advance(invoice.response[:checkout_status], status)))
  end

  # Decides what to do with the invoice's current session, if any:
  # [:reuse, url] / [:new] / [:wait] (do not charge now).
  def previous_session(invoice, unit_amount)
    session_id = invoice.response[:checkout_session_id]
    # No session: first attempt, or the last create was definitively rejected.
    return [:new] if session_id.blank?

    session = ::Stripe::Checkout::Session.retrieve(session_id, { api_key: api_key })
    case session.status
    when 'open'
      return [:reuse, session.url] if same_charge?(invoice, session, unit_amount) && session.url.present?

      ::Stripe::Checkout::Session.expire(session_id, {}, { api_key: api_key })
      set_status(invoice, 'expired')
      [:new]
    when 'complete'
      # Record a completion whose webhook has not arrived yet.
      apply_session(invoice, session)
      return [:wait] if invoice.paid?
      # complete/unpaid is an async payment still clearing; only a failure
      # confirmed for THIS session (async_payment_failed) allows a retry.
      invoice.response[:checkout_status] == 'failed' ? [:new] : [:wait]
    else # expired
      set_status(invoice, 'expired')
      [:new]
    end
  rescue ::Stripe::StripeError => e
    # Inconclusive: the previous session may still be payable, so never open
    # a second one; the next send retries with the same attempt.
    Rails.logger.warn("Stripe: could not check/expire #{session_id} for Invoice##{invoice.id}: #{e.message}")
    [:wait]
  end

  def same_charge?(invoice, session, unit_amount)
    amount = invoice.response[:checkout_amount_cents] || session.try(:amount_total)
    session_currency = invoice.response[:checkout_currency] || session.try(:currency)
    amount.to_i == unit_amount && session_currency.to_s.downcase == currency
  end

  # Persists the next attempt (key and charge parameters) BEFORE calling
  # Stripe, so a lost response is retried with exactly the same request.
  def start_attempt(invoice, unit_amount)
    attempt = invoice.response[:checkout_attempt].to_i + 1
    invoice.update_column(:response, invoice.response.merge(
      checkout_attempt: attempt,
      checkout_idempotency_key: idempotency_key(invoice, attempt),
      checkout_amount_cents: unit_amount,
      checkout_currency: currency,
      checkout_previous_session_id: invoice.response[:checkout_session_id],
      checkout_session_id: nil,
      checkout_status: 'creating'
    ).compact)
  end

  # Creates the session of the current `creating` attempt with its stored key
  # and parameters. Returns the URL, or nil. An inconclusive error (network,
  # timeout, 5xx, 409/429) keeps the attempt `creating` for a same-key retry;
  # a definitive 4xx rejection closes it (Stripe replays a rejected key, so the
  # next checkout needs a new attempt).
  def perform_create(invoice)
    r = invoice.response
    unit_amount = r[:checkout_amount_cents].to_i
    params = {
      mode: 'payment',
      client_reference_id: invoice.id.to_s,
      metadata: { invoice_id: invoice.id },
      payment_intent_data: { metadata: { invoice_id: invoice.id } },
      line_items: [{
        quantity: 1,
        price_data: {
          currency: r[:checkout_currency],
          unit_amount: unit_amount,
          product_data: { name: title(invoice) },
        },
      }],
      success_url: "#{invoice.back_urls(:success)}?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: invoice.back_urls(:cancel),
    }
    email = customer_email(invoice)
    params[:customer_email] = email if email.present?

    key = r[:checkout_idempotency_key].presence || idempotency_key(invoice, r[:checkout_attempt].to_i)
    session = ::Stripe::Checkout::Session.create(params, { api_key: api_key, idempotency_key: key })
    invoice.update!(response: invoice.response.merge(checkout_session_id: session.id, checkout_status: 'open'))
    session.url
  rescue ::Stripe::StripeError => e
    Rails.logger.error("Stripe: checkout failed for Invoice##{invoice.id}: #{e.class}: #{e.message}")
    if definitive_rejection?(e)
      invoice.update_column(:response, invoice.response.merge(checkout_status: 'rejected'))
    end
    nil
  end

  def definitive_rejection?(error)
    status = error.http_status.to_i
    (400..499).cover?(status) && ![409, 429].include?(status)
  end

  # Environment-prefixed so a restored backup or another environment sharing
  # the Stripe account cannot replay a stored result for a different invoice.
  def idempotency_key(invoice, attempt)
    "#{Rails.env}-invoice-#{invoice.id}-attempt-#{attempt}"
  end

  # The signature proved the event comes from the Stripe account owning this
  # endpoint's secret, so any invoice whose payment resolves to that same
  # secret is ours (several stores' payments with blank tokens share the ENV
  # secret, but only one endpoint can be registered for it). A payment with a
  # distinct secret belongs to another account and is never touched.
  def invoice_from_session(session)
    same_account(Invoice.find_by(id: session_invoice_id(session)))
  end

  def same_account(invoice)
    return nil if invoice.nil?
    return invoice if invoice.payment_id == payment.id

    other = invoice.payment_method
    invoice if other.is_a?(self.class) && other.webhook_secret.present? && other.webhook_secret == webhook_secret
  end

  def session_invoice_id(session)
    session.try(:metadata).try(:[], :invoice_id).presence || session.try(:client_reference_id)
  end

  def invoice_from_charge(charge)
    invoice_id = charge.try(:metadata).try(:[], :invoice_id).presence
    invoice = same_account(Invoice.find_by(id: invoice_id)) if invoice_id
    return invoice if invoice

    intent = charge.try(:payment_intent)
    return nil if intent.blank?
    Invoice.where("response LIKE ?", "%#{Invoice.sanitize_sql_like(intent)}%")
           .find { |inv| inv.response[:payment_intent_id] == intent && same_account(inv) }
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
