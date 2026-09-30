class InvoiceItem < ApplicationRecord
  enum :state, {normal: 0, conciliate:1, conciliated:2, error:3}

  belongs_to :invoice,    optional:true
  belongs_to :account,    optional:true
  belongs_to :trace,      optional:true
  belongs_to :plan_usage, optional:true

  has_many :loggings,      as: :resourceable, dependent: :destroy

  include LibEnums

  delegate :store, to: :invoice, allow_nil: true
  delegate :name,  to: :invoice, allow_nil: true

  after_save :calculate_invoice

  def calculate_invoice
    invoice.balance_update if invoice.present?
  end

  def invoice_date
    name_split = invoice.name.split("-", 2).try(:last)
    DateTime.parse(name_split + "-01 00:00:00 #{DateTime.current.zone}")
  end

  def can_conciliate?
    (self.normal? || !self.conciliated?) and plan_usage&.usageable&.percent? and invoice.client?
  end

  def can_conciliated?
    self.conciliated? || plan_usage&.usageable&.fixed? and invoice.client?
  end

end