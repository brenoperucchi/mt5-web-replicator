require 'lib_enums'

class Trace < ApplicationRecord
  ENUMS = %w(kind)

  include LibEnums

  enum kind:  {telegram: 0, copy: 1}

  store :settings, accessors: [:telegram_option, :telegram_image, :take_profit_limit, 
                               :telegram_api_id, :telegram_api_hash, :telegram_api_number]

  has_many :orders, :class_name => "Order", :foreign_key => "trace_id", dependent: :destroy
  has_many :transactions#, :through => :orders, :source => :transactions
  has_many :messages, :class_name => "Message", :foreign_key => "trace_id"

  has_many :instruments, :class_name => "Instrument", :foreign_key => "trace_id", dependent: :destroy
  belongs_to :store, optional: true

  scope :active,   ->{ where.not(active_at:nil)}
  # scope :telegram, ->{ where(kind:'telegram')}

  has_many :permissions, dependent: :destroy
  has_many :accounts, :through => :permissions#, :source => :slave

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

  def off 
    self.update_column(:active_at, nil)
  end

  def self.disable
    Trace.all.map(&:off)
  end


  def hit_rate(type)
    gain = transactions.send(type).try(:gain).try(:count).to_f
    loss = transactions.send(type).try(:loss).try(:count).to_f
    return 0 if loss == 0 or gain == 0
    number_with_precision((gain / loss) * 100, precision: 2) 
  end

end