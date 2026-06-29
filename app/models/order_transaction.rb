class OrderTransaction < ApplicationRecord
  belongs_to :order
  belongs_to :master, class_name: 'Transaction', foreign_key: :transaction_id, dependent: :destroy
end
