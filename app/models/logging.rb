class Logging < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :loggerable, polymorphic: true
  # has_one :account, :through => :loggerable, :source => :account

  def state
    klass_name = loggerable.class.name.to_s
    if klass_name.include?("Transaction")
      YAML.load(content)["action"]
    elsif klass_name.include?('Account')
      "COPY"
    end
  end

  def detect_closed?
    YAML.load(content)["action"] == "CLOSED" if loggerable.class.name == "TransactionSlave"
  end

  def account
    klass_name = loggerable.class.name.to_s
    if klass_name.include?("Transaction")
      loggerable.try(:account).try(:name)
    elsif klass_name.include?('Account')
      loggerable.try(:name)
    end
  end
end
