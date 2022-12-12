class InvoiceItem < ApplicationRecord

  # store :settings, accessors: [:name]

  belongs_to :invoice


  after_save :calculate_invoice

  def calculate_invoice
    invoice.balance_update if invoice.present?
  end

end
