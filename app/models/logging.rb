class Logging < ApplicationRecord

  has_ancestry

  has_many :orders
  has_many :transactions, through: :orders, source: :transactions

  belongs_to :user, optional: true
  
  # belongs_to :order,    optional: true
  belongs_to :account,  optional: true
  # belongs_to :message,  optional: true
  # belongs_to :copy,     optional: true
  # belongs_to :slave,    optional: true

  belongs_to :loggerable, polymorphic: true, optional:true
  belongs_to :resourceable, polymorphic: true, optional:true
  belongs_to :version, :class_name => "PaperTrail::Version", :foreign_key => "version_id", optional: true

  def detect_closed?
    YAML.load(content)["action"] == "CLOSED" if loggerable.class.name == "TransactionSlave"
  end


  # def loggings
    
  # end

  # def account
  #   klass_name = loggerable.class.name.to_s
  #   if klass_name.include?("Transaction")
  #     loggerable.try(:account).try(:name)
  #   elsif klass_name.include?('Account')
  #     loggerable.try(:name)
  #   end
  # end


end