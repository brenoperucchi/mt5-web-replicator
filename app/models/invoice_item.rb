class InvoiceItem < ApplicationRecord

  # store :settings, accessors: [:name]

  belongs_to :invoice

end
