class InvoiceItem < ApplicationRecord

  # store :settings, accessors: [:name]

  belongs_to :invoice,    optional:true
  belongs_to :account,    optional:true
  belongs_to :trace,      optional:true
  belongs_to :store,      optional:true
  belongs_to :plan_usage, optional:true

  has_many :loggings,      as: :resourceable, dependent: :destroy

  enum state: {normal: 0, conciliate:1, conciliated:2, error:3}

  after_save :calculate_invoice

  def calculate_invoice
    invoice.balance_update if invoice.present?
  end


  def conciliate_metatrader_on
    if self.normal?
      date       = invoice_date
      date_start = date.beginning_of_month.beginning_of_day.to_s 
      date_ended = date.end_of_month.end_of_day.to_s 

      account.api_send_orders_history_date_start = date_start
      account.api_send_orders_history_date_end = date_ended
      account.api_send_orders_history = true
      account.save
    end
  end

  def conciliate_metatrader_off
    account.api_send_orders_history = false
    account.save
  end

  def conciliate_metatrader(presenter)
    date = invoice_date
    amount_presenter = presenter.conciliate_amount

    plan_usage.amount_calculate(date, nil, account.contract_volume_use, amount_presenter)
    self.amount = plan_usage.amount_proportional
    timestamp = I18n.l DateTime.now, format: :short8
    self.description << "\n#{timestamp} - Metatrader: #{number_with_precision amount_presenter} * Percentual Plan #{number_with_precision plan_usage.amount, significant:true, precision: 2}%"
    # self.description << "\n#{timestamp} - Conciliação valor: #{number_with_precision self.amount}"
  end

  def invoice_date
    name_split = invoice.name.split("-", 2).try(:last)
    DateTime.parse(name_split + "-01 00:00:00 #{DateTime.now.zone}")
  end


  def can_conciliate?
    (self.normal? || !self.conciliated?) and plan_usage&.usageable&.percent?
  end

  def can_conciliated?
    self.conciliated? || plan_usage&.usageable&.fixed?
  end

end