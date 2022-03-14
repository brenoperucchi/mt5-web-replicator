class Invoice < ApplicationRecord
  
  enum state: {pending: 0, paid: 1, denied:2}
  
  store :settings, accessors: [:email]

  # belongs_to :ownerable, polymorphic: true
  belongs_to :invoiceable, polymorphic: true
end
