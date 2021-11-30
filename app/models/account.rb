class Account < ApplicationRecord
  enum state: {disable: 0, enable: 1}

  belongs_to :store
  has_many :permissions
  has_many :traces,       through: :permissions#, source: :trace 
  has_many :orders,       through: :traces, source: :orders

  has_many :morphics
  has_many :transactions, through: :morphics, source: :tmaster
  has_many :slaves,       through: :transactions, source: :transaction_slaves, class_name:'TransactionSlave'

end