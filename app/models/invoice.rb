require 'lib_enums'
class Invoice < ApplicationRecord

  include LibEnums
  include ActionView::Helpers::NumberHelper

  has_paper_trail on: [:create, :update]

  delegate :stripe_product_id, :stripe_customer_id, to: :store
  delegate :email, to: :invoiceable, allow_nil: true
  # delegate :trace, to: :plan_usage, allow_nil: true
  
  enum kind:  {system:0, client:1}
  enum state: {pending: 0, to_paid:1, paid: 2, denied:3, refunded:4}
  
  store :settings, accessors: [:email, :payment_link, :back_url]

  serialize :response

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


  def invoice_send
    payment_method = self.payment.payment_method.provider(self.payment)
    payment_method.checkout(self)
    self.update(payment_link: redirect_url)
    return payment_method
  end

  def customer
    self.invoiceable if respond_to?(:invoiceable) and self.invoiceable.is_a?(Customer)
  end


  def payment_method
    self.payment.payment_method.provider(self.payment)
  end

  def response
    read_attribute(:response) || {}
  end

  def redirect_url
    return false if response[:preference].empty?
    if Rails.env.development? || Rails.env.test?
      response[:preference]["sandbox_init_point"] || false
    else
      response[:preference]["init_point"] || false
    end
  end

  def check_payment
    logging = loggings.where(state: 'opened').take
    if logging
      payment_method = payment.payment_method.provider(payment)
      payment_method.check_payment(ActionController::Parameters.new(eval logging.content))
    end
    self.payment_status
  end

  def payment_status(response_status=nil)
    response_status ||= self.response[:response].dig("order_status")
    case response_status
    when 'approved', 'paid'
      self.paid!
    when 'rejected'
      self.denied!
    when 'refunded', 'charged_back'
      self.refunded!
    end

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

    timestamp = I18n.l DateTime.current, format: :short8

    if customer_plan.fixed?# and customer_plan.monthly?
      # invoice.back_url = "mercadopago/back_urls/success/#{self.id}"
      amount = plan_usage.amount_proportional 
      description = "#{timestamp} - Contratos: #{account.contract_volume_use} * Valor #{number_with_precision plan_usage.amount_proportional}"
    elsif customer_plan.percent?
      # invoice.back_url = "panel/dashboard/back_urls/success/#{self.id}"
      account.search_date_begin = date.beginning_of_month
      account.search_date_end = date.end_of_month
      data_profit = account.data_profit(:slaves, trace)
      amount = data_profit * (customer_plan.amount_use.to_f / 100)
      description = "#{timestamp} - Sistema: #{number_with_precision data_profit} * Percentual Plan #{number_with_precision customer_plan.amount_use.to_f, significant:true, precision: 2}%"
    end
  
    if self.save
      item = self.items.find_or_create_by(handle: :customer_monthly_payment, account: account, trace: trace, plan_usage:plan_usage)
      item.update(amount: amount, description: description)
      plan_usage.update_next_charged
    end
  end

  def back_urls(kind)
    if self.invoiceable.owner? 
      "https://#{store.domain_url}/mercadopago/back_urls/#{kind.to_s}/#{self.id}"
    elsif self.invoiceable.customer?
      "https://#{store.domain_url}/panel/dashboard/back_url/#{store.url}/#{kind.to_s}/#{self.id}"
    end
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