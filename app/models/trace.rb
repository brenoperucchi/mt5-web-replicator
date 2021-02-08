class Trace < ApplicationRecord
  # acts_as_taggable_on :volumes
  
  # TAKE_PROFIT = %w{normal agressive superagressive} 

  store :settings, accessors: [:telegram_option, :telegram_image, :take_profit_limit, :volumes] 

  has_many :orders, :class_name => "Order", :foreign_key => "trace_id"
  has_many :messages, :class_name => "Message", :foreign_key => "trace_id"
  has_many :slaves, :class_name => "Slave", :foreign_key => "trace_id"
  belongs_to :store, optional: true

  scope :active, ->{ where.not(active_at:nil)}

  # validates_presence_of :take_profit, :on => :create#, :message => "can't be blank"

  def volumes
    self.settings['volumes'] || ""
  end

  def active
    active_at.present?
  end

  def active=(value)
    self.active_at = (value == "1") ? Time.current : nil
  end

  alias_method :active?, :active

  def symbol_list_dict
    pairs = self.symbol_list.strip.gsub("\r", '')
    pairs = pairs.gsub("\t", '')
    pairs = pairs.split("\n").map{|pair| pair.split(':')}.map{|k,v| [k.strip, v.strip]}
    result = Hash[pairs]
  end

end