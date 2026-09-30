class Invoice < ApplicationRecord

  include LibEnums
  include ActionView::Helpers::NumberHelper

  has_paper_trail on: [:create, :update]

  delegate :stripe_product_id, :stripe_customer_id, to: :store
  delegate :email, to: :invoiceable, allow_nil: true
  # delegate :trace, to: :plan_usage, allow_nil: true
  
  enum :kind, {system:0, client:1}
  enum :state, {pending: 0, to_paid:1, paid: 2, denied:3, refunded:4}
  
  store :settings, accessors: [:email, :payment_link, :back_url]

  serialize :response, coder: YAML

  # belongs_to :ownerable, polymorphic: true
  belongs_to :store
  belongs_to :payment
  belongs_to :plan_usage, optional:true
  belongs_to :invoiceable, polymorphic: true, optional:true

  has_many :items, :class_name => "InvoiceItem", :foreign_key => "invoice_id", dependent: :destroy
  has_many :loggings,      as: :loggerable, dependent: :destroy

  accepts_nested_attributes_for :items, reject_if: :all_blank, allow_destroy: true


  def balance_update
    self.update(amount: items.to_a.sum(&:amount))  
  end


  # Asks the payment provider for a hosted checkout URL and stores it as the
  # invoice payment link. Returns the URL, or false when no provider is
  # available for this invoice's payment method.
  def invoice_send
    provider = payment_method
    return false if provider.nil?

    url = provider.checkout(self)
    return false if url.blank?

    update(payment_link: url)
    url
  end

  def customer
    self.invoiceable if respond_to?(:invoiceable) and self.invoiceable.is_a?(Customer)
  end


  def payment_method
    payment&.payment_method&.provider(payment)
  end

  def response
    read_attribute(:response) || {}
  end

  def redirect_url
    payment_link.presence
  end

  # Allowed provider-driven transitions: target state => states it may come
  # from. Anything else (e.g. paid -> denied, refunded -> paid) is ignored so
  # late or out-of-order webhooks cannot move an invoice backwards.
  PAYMENT_TRANSITIONS = {
    'paid'     => %w[pending to_paid denied],
    'denied'   => %w[pending to_paid],
    'refunded' => %w[paid],
  }.freeze

  # Applies a provider-neutral payment status (:paid, :denied, :refunded)
  # under a row lock, so concurrent webhooks are serialized. Returns true when
  # the invoice ends in the requested state.
  def payment_status(status)
    status = status.to_s
    return false unless PAYMENT_TRANSITIONS.key?(status)

    with_lock do
      next true if state == status
      unless PAYMENT_TRANSITIONS[status].include?(state)
        Rails.logger.info("Invoice##{id}: ignored payment status #{state} -> #{status}")
        next false
      end
      update_column(:state, Invoice.states[status])
      true
    end
  end

  CHECKOUT_RECONCILE_OUTCOMES = %w[paid failed expired].freeze

  # Operator-only recovery (see README "Recovering an inconclusive attempt"):
  # records the financial outcome of the current checkout attempt, confirmed
  # by hand in the ORIGINAL Stripe account, and only then detaches its session
  # so the next send can open a new attempt. Never call it on a guess.
  def reconcile_checkout!(outcome:, note:)
    outcome = outcome.to_s
    raise ArgumentError, "outcome must be one of #{CHECKOUT_RECONCILE_OUTCOMES.join('/')}" unless CHECKOUT_RECONCILE_OUTCOMES.include?(outcome)
    raise ArgumentError, 'note is required' if note.blank?

    with_lock do
      r = response
      update!(response: r.merge(
        checkout_status: outcome,
        checkout_previous_session_id: r[:checkout_session_id] || r[:checkout_previous_session_id],
        checkout_session_id: nil,
        checkout_reconciled: { outcome: outcome, note: note.to_s, at: Time.current.iso8601,
                               session_id: r[:checkout_session_id], idempotency_key: r[:checkout_idempotency_key],
                               previous_status: r[:checkout_status] }
      ))
      payment_status(:paid) if outcome == 'paid'
    end
    self
  end

  def customer_calculate(customer, date, month_proporcional = nil)
    customer.accounts.slave.each do |account|
      account.traces.each do |trace|
        account_calculate(account, trace, date, month_proporcional)
      end
    end
  end

  def account_calculate(account, trace, date, month_proporcional = nil)
    date_due_at = (DateTime.parse(self.name[4..] + "-01 00:00:00 #{DateTime.current.zone}") + 1.month).beginning_of_month.beginning_of_day
    self.due_at = date_due_at + (trace.customer_plan.due_at_dates.to_i - 1).days

    data_profit = account.data_profit(:slaves, trace)
    plan_usage = account.add_account_trace_to_planusage(trace, trace.customer_plan)#.each do |plan_usage|
    plan_usage.amount_calculate(date, month_proporcional, data_profit)
    customer_plan = plan_usage.usageable

    self.payment = customer_plan.payment
    # self.plan_usage = plan_usage

    # Item descriptions are persisted, so write them in the store's language.
    item_locale = store.try(:language).presence_in(I18n.available_locales.map(&:to_s)) || I18n.default_locale
    timestamp = I18n.l DateTime.current, format: :short8, locale: item_locale

    if customer_plan.fixed?# and customer_plan.monthly?
      amount = plan_usage.amount_proportional 
      description = I18n.t('invoice_items.fixed_description', locale: item_locale, timestamp: timestamp,
                           contracts: account.contract_volume_use, amount: number_with_precision(plan_usage.amount_proportional))
    elsif customer_plan.percent?
      account.search_date_begin = date.beginning_of_month
      account.search_date_end = date.end_of_month
      data_profit = account.data_profit(:slaves, trace)
      amount = data_profit * (customer_plan.amount_use.to_f / 100)
      description = I18n.t('invoice_items.percent_description', locale: item_locale, timestamp: timestamp,
                           profit: number_with_precision(data_profit),
                           percent: number_with_precision(customer_plan.amount_use.to_f, significant: true, precision: 2))
    end
  
    if self.save
      item = self.items.find_or_create_by(handle: :customer_monthly_payment, account: account, trace: trace, plan_usage:plan_usage)
      item.update(amount: amount, description: description)
      plan_usage.update_next_charged
    end
  end

  # Where the payment provider sends the customer back after checkout.
  # kind: :success, :failure, :pending or :cancel
  def back_urls(kind)
    "https://#{store.domain_url}/payments/#{self.id}/return/#{kind}"
  end


  def self.generate_month_customers(date = nil)
    timestamp = I18n.l DateTime.current, format: :short8
    puts "#{timestamp} - Runner Invoice.generate_month"
    Customer.customer.user.not_deleted.each do |customer|
      customer.create_invoice(date)
    end

    self.conciliate_invoice_items
  end

  def self.conciliate_invoice_items
    timestamp = I18n.l DateTime.current, format: :short8
    puts "#{timestamp} - Runner Invoice.conciliate_invoice_items"
    Invoice.pending.each do |invoice|
      invoice.conciliate_request
    end
  end

  def conciliate_request
    items.each do |item|
      next if item.account.nil?
      if item.can_conciliated?
        # item.conciliated!
      elsif item.can_conciliate? and not items.conciliate.exists?
        item.conciliate! if item.conciliate_metatrader_on
      end
    end

    to_paid! if items.all? { |item| item.can_conciliated? }
  end

end