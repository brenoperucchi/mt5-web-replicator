class Logging < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :loggerable, polymorphic: true
  # has_one :account, :through => :loggerable, :source => :account

  def state
    YAML.load(self.content)['action']
  end

  def account
    loggerable.try(:account).try(:name)
  end
end
