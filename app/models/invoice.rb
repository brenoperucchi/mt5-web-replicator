require 'lib_enums'
class Invoice < ApplicationRecord

  include LibEnums
  include ActionView::Helpers::NumberHelper

  has_paper_trail 

  delegate :stripe_product_id, :stripe_customer_id, to: :store
  delegate :email, to: :invoiceable, allow_nil: true
  # delegate :trace, to: :plan_usage, allow_nil: true
  
  enum state: {pending: 0, opened:1, paid: 2, denied:3, refunded:4}
  
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
      self.update(state: 'paid')
    when 'rejected'
      self.update(state: 'denied')
    when 'refunded', 'charged_back'
      self.update(state: 'refunded')
    end

  end

  def customer_calculate(customer, date_today, month_proporcional = nil)
    customer.accounts.each do |account|
      account.traces.each do |trace|
        account_calculate(account, trace, date_today, month_proporcional)
      end
    end
  end

  def account_calculate(account, trace, date_today, month_proporcional = nil)
    date_due_at = (DateTime.parse(self.name[3..] + "-01 00:00:00 #{DateTime.now.zone}") + 1.month).beginning_of_month.beginning_of_day
    self.due_at = date_due_at + (trace.customer_plan.due_at_dates.to_i - 1).days

    plan_usage = account.add_account_trace_to_planusage(trace, trace.customer_plan)#.each do |plan_usage|
    plan_usage.amount_calculate(date_today, month_proporcional)
    
    customer_plan = plan_usage.usageable

    self.payment = customer_plan.payment
    self.plan_usage = plan_usage


    if customer_plan.fixed?# and customer_plan.monthly?
      # invoice.back_url = "mercadopago/back_urls/success/#{self.id}"
      amount = plan_usage.amount_proportional 
      description = "Contratos: #{account.contract_volume} * Valor #{number_with_precision plan_usage.amount_proportional}"
    elsif customer_plan.percent?
      # invoice.back_url = "panel/dashboard/back_urls/success/#{self.id}"
      account.search_date_begin = date_today.beginning_of_month
      account.search_date_end = date_today.end_of_month
      data_profit = account.data_profit(:slaves, trace)
      amount = data_profit * (customer_plan.amount_use.to_f / 100)
      description = "Lucro do mês: #{number_with_precision data_profit} * Percentual Plan #{number_with_precision customer_plan.amount_use.to_f, significant:true, precision: 2}%"
    end
  
    if self.save
      item = self.items.find_or_create_by(name: :customer_monthly_payment, account: account, trace: trace)
      item.update(amount: amount, description: description)
      plan_usage.update_next_charged
    end
  end

  def back_urls(kind)
    if self.plan_usage.usageable.fixed?
      "https://#{store.domain_url}/mercadopago/back_urls/#{kind.to_s}/#{self.id}"
    elsif self.plan_usage.usageable.percent?
      "https://#{store.domain_url}/panel/dashboard/back_url/#{store.url}/#{kind.to_s}/#{self.id}"
    end
  end


  def conciliate_orders(orders_presenter, account)
    amount_items = items.where(account: account).to_a.sum(&:amount)
    if amount_items != orders_presenter.conciliate_amount
      conciliate_amount = orders_presenter.conciliate_amount - amount_items
      if self.items.create(name: :conciliate, account: account, amount: conciliate_amount, description: "Conciliação de Ordens - Account: #{account.name}")
        self.balance_update
      end
    end
  end

end