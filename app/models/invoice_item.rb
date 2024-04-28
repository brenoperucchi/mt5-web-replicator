class InvoiceItem < ApplicationRecord

  # store :settings, accessors: [:name]

  belongs_to :invoice, optional:true
  belongs_to :account, optional:true
  belongs_to :trace, optional:true
  belongs_to :store, optional:true


  after_save :calculate_invoice

  def calculate_invoice
    invoice.balance_update if invoice.present?
  end

end