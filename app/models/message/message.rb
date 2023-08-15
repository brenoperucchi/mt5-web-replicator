require "ancestry"

class Message::Message < ApplicationRecord
  self.table_name = "messages"
  has_ancestry

  serialize :content
  serialize :params

  
  # has_many :orders
  has_and_belongs_to_many :orders
  has_and_belongs_to_many :traces 

  has_many :transactions,   through: :orders, source: :transactions
  has_many :slaves,   through: :orders, source: :slave
  
  has_many :loggings, as: :loggerable, dependent: :destroy

  belongs_to :store,   optional: true
  belongs_to :account, optional: true
  # belongs_to :trace, optional: true

  before_destroy { Order.where(id:[order_ids]).destroy_all }

  def kind
    loggings.try(:first).try(:state)
  end

  def all_loggings
    loggings.try(:first).try(:subtree)
  end

  def params_copy(key = nil)
    if self.content.is_a?(String)
      begin
        YAML.load(content)[key.to_s]
      rescue
        return Hash.new
      end
    end
  end


  def params_url(key = nil)
    if self.content.is_a?(String)
      begin
        YAML.load(params)[key.to_s]
      rescue
        return Hash.new
      end
    end
  end


  def request_url
    YAML.load(params)[:request_url] || nil
  end



end