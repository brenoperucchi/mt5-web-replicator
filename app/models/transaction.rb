require 'telegram/bot'
class Transaction < ApplicationRecord
  include Telegram::Util

  # attr_accessor :mfe, :mae, :time_trader

  has_paper_trail 
  # versions: {
  #   class_name: 'Track'
  # }

  belongs_to :order, optional:true
  belongs_to :message, class_name: 'Message::Metatrader', foreign_key: :message_id, optional:true
  belongs_to :account, optional:true
  belongs_to :trace, optional:true
  belongs_to :deal, optional:true

  has_many :loggings, as: :loggerable, dependent: :destroy
  has_many :slaves,   through: :order,    source: :slaves
  has_many :accounts, through: :order,    source: :accounts

  has_many :statistics, as: :statisticable, dependent: :destroy

  scope :closed,      ->{where(state: 'closed')}
  scope :closed_info,      ->{where(state: 'closed_info')}
  scope :finish,      ->{where(state: ['closed', 'error'])}
  scope :executed,    ->{where(state: 'executed')}
  scope :error,    ->{where(state: 'error')}
  scope :not_error,    ->{where.not(state: 'error')}
  scope :closed_error,  ->{where(state: ['closed', 'error'])}
  scope :not_closed,  ->{where.not(state: ['closed', 'error'])}
  scope :buy,   ->{where(ordertype: 0)}
  scope :sell,  ->{where(ordertype: 1)}
  scope :gain,  ->{where('transactions.profit >= 0')}
  scope :loss,  ->{where('transactions.profit < 0')}

  scope :pending_executed,  ->{where(state: [:pending, :executed])}

  # before_create :set_symbol
  after_create  :validate_restriction
  # validate :restrict_symbol?, :restrict_nil_instrument?, on: :create


  class << self
    def ransackable_scopes(_auth_object = nil)
      %i[profit_search ticket_search]
    end
  end

  def self.profit_search(value)
    self.where(profit:0..value.to_f)
  end

  def self.ticket_search(value)
    self.where("CAST(ticket as TEXT) ILIKE ?", "%#{value}%")
  end


  state_machine :initial => :pending do
    after_transition :pending => :executed,                    :do => :update_state
    after_transition [:pending, :executed] => :closed,         :do => :update_state
    after_transition [:pending, :executed, :closed] => :error, :do => :update_state
    # after_transition :executed => :closed, :do => :break_even
    # after_transition [:executed, :ordered] => :pending, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :close do
      transition [:pending, :executed, :closed_info] => :closed
    end
    event :close_info do
      transition [:closed] => :closed_info
    end
    event :restart do
      transition [:executed, :error, :closed] => :pending
    end
    event :erro do
      transition [:pending, :executed, :closed] => :error
    end
    
    state :error do
      def update_state(state)
        self.order.erro
      end
    end
    state :executed do
      def update_state(state)
        if self.restrict_magic_number?
          self.telegram_message(:OPEN)
        end
      end
    end

    state :closed do
      def update_state(state)
        self.telegram_message(:CLOSED)
        self.try(:order).try(:close)
        self.slaves.map(&:remove)
        return true
      end
    end
  end

  def telegram_message(state)
    chat_id = self.trace.store.telegram_bot_chat_id
    if chat_id.present?
      content = self.telegram_message_prepare(state)
      TelegramJob.perform_async(chat_id, content)
    end
  end

  def set_profit(order_params)
    if self.update(profit: profit)
      loggings.create(content:order_params, changeset: versions.last.changeset, version:version, state: 'MODIFY')
    end
  end

  def set_slaves_attributes(lot=nil, take_profit=nil, stop_loss=nil)
    self.slaves.each{|s| s.set_sl_and_tp_order(lot, take_profit, stop_loss)}
  end

  def set_lot_sl_tp(order_params)
    attributes = {lot: order_params["volume"], take_profit: order_params['take_profit'].to_f, stop_loss:order_params['stop_loss'].to_f, profit:order_params["profit"]}
    # attributes = {lot:lot, take_profit:take_profit, stop_loss:stop_loss}.compact
    self.attributes = attributes 
    if self.changes.present?
      chat_id = self.trace.store.telegram_bot_chat_id
      if chat_id.present?
        content = self.telegram_message_prepare(:MODIFY)
        TelegramJob.perform_async(chat_id, content)
      end

      # content = self.telegram_message_prepare(:MODIFY)
      # BotTelegram.send_message(self.trace.store.telegram_bot_chat_id, content)
    end
    
    if self.save
      loggings.create(content:order_params, changeset: versions.last.changeset, version:version, state: 'MODIFY')
      set_slaves_attributes(lot, take_profit, stop_loss)
    end
  end

  def set_mfe_mae(mfe, mae, time_trader)
    unless time_trader.nil? or mae.nil? or mfe.nil?
      # date_today = month.nil? ? DateTime.now : DateTime.now + eval(month)
      statistic_name = "#{time_trader.to_date.strftime("%Y-%m-%d")}"
      
      statistic = self.statistics.find_or_create_by(name: statistic_name, kind: :mfe)
      statistic.update(amount: mfe.to_f) if mfe > statistic.amount.to_f 

      statistic = self.statistics.find_or_create_by(name: statistic_name, kind: :mae)
      statistic.update(amount: mae.to_f) if mae < statistic.amount.to_f 
    end
  end  

  # def mae=(value)
  #   # date_today = month.nil? ? DateTime.now : DateTime.now + eval(month)
  #   statistic_name = "mae_#{time_trader.to_date.strftime("%Y-%m-%d")}"
    
  #   statistic = self.statistics.find_or_initialize_by(name: statistic_name)
  #   statistic.update(amount: value) if value < statistic.amount.to_f
  # end


  def meta_ordertype
    # "OP_" + ordertype.upcase
    case ordertype.downcase
    when "buy"
      0
    when 'sell'
      1
    when 'buy_limit'
      2
    when 'buy_stop'
      3
    when 'sell_limit'
      4
    when 'sell_stop'
      5
    end
  end

  def profit
    read_attribute(:profit).nil? ? 0 : read_attribute(:profit)
  end

  def set_symbol
    if order.trace.telegram?
      ## TODO - CHANGE FOR SEARCHING FOR EXACTLY SYMBOL ON INSTRUMENTS
      self.symbol = account.instruments.detect{|x| message.content.gsub(/\W/, '').upcase.include?(x[:symbol].upcase) }.try(:name)
    else
      self.symbol = account.instruments.find_by(symbol: message.serializer.symbol.try(:upcase)).try(:name)
    end
  end

  def restrict_magic_number?
    order.restrict_magic_number(self) or trace.restrict_magic_number(self)
    # unless self.account.magics_accept.blank?
    #   unless account.magics_accept.try(:split).try(:include?, magic_number)
    #     loggings.create(content:"Account #{account.name} Magic Number Restrict ##{magic_number}", changeset: versions.last.changeset, version:version, state: 'ERROR')
    #     self.erro!
    #   end
    # end
  end

  def validate_restriction
    # restrict_nil_instrument? 
    # restrict_symbol?
  end


  def api_request_attributes
    order.api_request_attributes(self)
  end

  def self.api_request_attributes(scope)
    return if scope.nil?
    self.send(scope).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 60.days)).collect{|t| t.api_request_attributes}.join('/')
  end

  # def restrict_nil_instrument?
  #   if symbol.nil?
  #       self.response = "Restrict Instrument"
  #       # errors.add(:symbol, "instrument nil")
  #       self.erro!
  #     end   
  # end

  # def restrict_symbol?
  #   if message.store.tag_list.map(&:downcase).include?(symbol.try(:downcase))
  #       self.response = "Restrict Symbol"
  #       # errors.add(:symbol, "store restrict symbol")
  #       self.erro!
  #     end
  # end


end