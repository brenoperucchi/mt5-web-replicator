class Logging < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :loggerable, polymorphic: true
  # has_one :account, :through => :loggerable, :source => :account

  def state
    
  end

  # def state
  #   if self.content.is_a?(Hash)
  #     object
  #   else
  #     YAML.load(self.content)['action']
  #   end
  # end

  def account
    loggerable.try(:account).try(:name)
  end
end
