class Deal < ApplicationRecord
  attr_accessor :profit_copy, :profit_slave

  belongs_to :account, optional:true
  belongs_to :store, optional:true
  belongs_to :trace, optional:true

  has_many :masters,  :class_name => "Transaction",      :foreign_key => "deal_id",  dependent: :destroy
  has_many :slaves,   :class_name => "TransactionSlave", :foreign_key => "deal_id",  dependent: :destroy


  def masterss
    self.send(:masters).select(:ticket)
  end

  # def profit_copy
  #   masters.closed.sum(&:profit)
  # end

  # def profit_slave
  #   slaves.closed.sum(&:profit)
  # end

  # def operation_copy
  #   masters.closed.count
  # end
  
  # def operation_slave
  #   slaves.closed.count
  # end

end
