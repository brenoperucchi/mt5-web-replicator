class Logging < ApplicationRecord

  has_ancestry

  store :settings, accessors:[:error_message, :error_backtrace]

  has_many :orders
  has_many :transactions, through: :orders, source: :transactions

  belongs_to :user, optional: true
  belongs_to :account,  optional: true

  belongs_to :loggerable, polymorphic: true, optional:true
  belongs_to :resourceable, polymorphic: true, optional:true
  belongs_to :version, :class_name => "PaperTrail::Version", :foreign_key => "version_id", optional: true

  def detect_closed?
    YAML.load(content)["action"] == "CLOSED" if loggerable.class.name == "TransactionSlave"
  end



end