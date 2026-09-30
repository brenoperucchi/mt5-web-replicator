class Deal < ApplicationRecord
  attr_accessor :ordertype

  belongs_to :account, optional:true
  belongs_to :store, optional:true
  belongs_to :trace, optional:true

  has_many :orders
  has_many :masters, :through => :orders, :source => :transactions
  has_many :slaves,  :through => :orders, :source => :slaves

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
  

  

end
