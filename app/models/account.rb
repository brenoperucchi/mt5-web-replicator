class Account < ApplicationRecord
  enum state: {disable: 0, enable: 1}
  enum kind:  {slave: 0, copy: 1}

  store :settings, accessors: [:magics_accept]

  belongs_to :store
  has_many :permissions
  has_many :traces,       through: :permissions#, source: :trace 
  has_many :orders,       through: :traces, source: :orders

  has_many :transactions,  class_name: 'Transaction',      foreign_key: 'account_id'
  has_many :slaves,       class_name: 'TransactionSlave', foreign_key: 'account_id'

  def trace_copy
    traces.find_by(kind: :copy) if self.copy?
  end

end