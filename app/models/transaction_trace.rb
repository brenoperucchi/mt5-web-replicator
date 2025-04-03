class TransactionTrace < ApplicationRecord
  belongs_to :master, class_name: 'Transaction'
  belongs_to :trace, class_name: 'Trace'
end
