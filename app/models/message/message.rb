require "ancestry"

class Message::Message < ApplicationRecord
  self.table_name = "messages"
  has_ancestry

  store :settings, accessors:[:request_url]

  serialize :content, coder: YAML
  serialize :params, coder: YAML
  
  has_and_belongs_to_many :orders, -> { distinct }
  has_and_belongs_to_many :traces, -> { distinct }

  has_many :transactions,   through: :orders, source: :transactions
  has_many :slaves,         through: :orders, source: :slaves
  
  has_many :loggings, as: :loggerable#, dependent: :destroy

  belongs_to :store,   optional: true
  belongs_to :account, optional: true

  def kind
    loggings.try(:first).try(:state)
  end

  def all_loggings
    loggings.try(:first).try(:subtree)
  end

  def params_copy(key = nil)
    if self.content.is_a?(String)
      begin
        json = clean_malformed_json(content)
        YAML.load(json)[key.to_s]
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

  def clean_malformed_json(json_str)
    # Procura por ocorrências de vírgulas extras após '{' dentro de "orders_open"
    cleaned_str = json_str.gsub(/("orders_open":\{),+/, '"orders_open":{')
    cleaned_str
  end

  def execute_again_conciliated
    account.update(api_send_orders_history: true)
    self.update(state: "pending")
    self.execute_conciliated
  end

  def execute_again
    account.update(api_send_orders_history: true)
    self.update(state: "pending")
    self.execute
  end

end