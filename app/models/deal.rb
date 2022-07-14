class Deal < ApplicationRecord
  attr_accessor :ordertype

  belongs_to :account, optional:true
  belongs_to :store, optional:true
  belongs_to :trace, optional:true

  has_many :masters,  :class_name => "Transaction",      :foreign_key => "deal_id",  dependent: :destroy
  has_many :slaves,   :class_name => "TransactionSlave", :foreign_key => "deal_id",  dependent: :destroy

  def ordertype
    case masters.try(:first).try(:ordertype)
    when "0"
      "BUY"
    when "1"
      "SELL"
    else
      'pending'
    end
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
