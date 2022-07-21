require 'lib_enums'
require 'algo_statistic'

class Trace < ApplicationRecord

  attr_accessor :search_date_begin, :search_date_end

  ENUMS = %w(kind)

  include LibEnums
  include AlgoStatistic

  enum kind:  {telegram: 0, copy: 1}

  store :settings, accessors: [:telegram_option, :telegram_image, :take_profit_limit, 
                               :telegram_api_id, :telegram_api_hash, :telegram_api_number]

  has_many :deals, dependent: :destroy
  has_many :masters, :through => :deals, :source => :masters
  has_many :slaves,  :through => :deals, :source => :slaves

  has_many :orders, dependent: :destroy
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

  def masters_profit
    masters_filter(masters.closed).sum(:profit)
  end

  def masters_total
    masters_filter(masters.where(state: [:closed, :error]))
  end

  def masters_scope(type, scope)
    masters_filter(self.send(type).closed).send(scope)
  end


  def masters_filter(scoped)
    if self.search_date_begin and self.search_date_end
      scoped.where(created_at: search_date_begin..search_date_end)
    else
      scoped
    end
  end


  def profit_trade(type)
    trades = masters_filter(self.send(type).closed).try(:count).to_f
    gain_trades = masters_filter(self.send(type).closed.try(:gain)).try(:count).to_f
    AlgoStatistic.profit_trade(trades, gain_trades)
  end

  def loss_trade(type)
    trades = masters_filter(self.send(type).closed).try(:count).to_f
    loss_trades = masters_filter(self.send(type).closed).try(:loss).try(:count).to_f
    AlgoStatistic.loss_trade(trades, loss_trades)
    # result = (loss_trades/trades)
    # result = (result * 100).round(2)
    # result.nan? ? 0 : result
  end

  def pay_off(type)
      gain = masters_filter(self.send(type).closed).try(:gain).sum(:profit).abs
      gain_operation = masters_filter(self.send(type).closed).try(:gain).try(:count).to_f
      loss = masters_filter(self.send(type).closed).try(:loss).sum(:profit).abs
      loss_operation = masters_filter(self.send(type).closed).try(:loss).try(:count).to_f
      AlgoStatistic.pay_off(gain, gain_operation, loss, loss_operation)
      # result = (gain/gain_operation)/(loss/loss_operation)
      # result.nan? ? 0 : result

  end

  def profit_factor(type)
    AlgoStatistic.profit_factor(profit_trade(type), loss_trade(type), pay_off(type))
    # begin
    #   (profit_trade(type)/loss_trade(type)*pay_off(type))    
    # rescue
    #   0
    # end
  end


  def drawdown(type)
    scoped = masters_filter(masters_filter(self.send(type).closed).order(created_at: :desc))
    AlgoStatistic.drawdown(scoped)

    # drawdown_balance = 0
    # drawdown_max = 0
    # # drawdown_max = 0

    # self.send(type).closed.order(created_at: :desc).each do |association|
    #   value = association.profit.to_f
    #   # puts "-------------------------------------"
    #   # puts "Value   #{value.round(2)}"
    #   # puts "Drawdown balance   #{drawdown_balance.round(2)}"
    #   # puts "Drawdown max #{drawdown_max.round(2)}"

    #   if value < 0 
    #     drawdown_balance = drawdown_balance + value
        
    #     if drawdown_balance < drawdown_max
    #       drawdown_max = drawdown_balance
    #     end

    #   else
    #     # puts "Drawdown balance   #{drawdown_balance.round(2)}"
    #     # puts "Value   #{value.round(2)}"
    #     # puts "drawdown_balance + value = #{(drawdown_balance + value).round(2)} " + "> 0}"
    #     drawdown_balance = drawdown_balance + value
    #     if drawdown_balance > 0
    #       drawdown_balance = 0 
    #     end
    #   end
    #   # puts "Drawdown max #{drawdown_max.round(2)}"
    #   # puts "Drawdown balance   #{drawdown_balance.round(2)}"
    #   # puts "-------------------------------------"
    #   # association.profit.to_f < 0 ? drawdown_balance = association.profit + drawdown_balance  : drawdown_balance
    # end
    # drawdown_max
  end

end