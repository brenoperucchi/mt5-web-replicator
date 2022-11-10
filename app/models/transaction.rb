require 'telegram/bot'
class Transaction < ApplicationRecord
  include Telegram::Util

  has_paper_trail 
  # versions: {
  #   class_name: 'Track'
  # }

  belongs_to :order, optional:true
  belongs_to :message
  belongs_to :account, optional:true
  belongs_to :trace, optional:true
  belongs_to :deal, optional:true

  has_many :loggings, as: :loggerable, dependent: :destroy
  has_many :slaves,   through: :order,    source: :slaves
  has_many :accounts, through: :order,    source: :accounts

  scope :closed,      ->{where(state: 'closed')}
  scope :finish,      ->{where(state: ['closed', 'error'])}
  scope :executed,    ->{where(state: 'executed')}
  scope :error,    ->{where(state: 'error')}
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

  state_machine :initial => :pending do
    # after_transition [:pending] => [:executed, :closed], :do => lambda { |transaction| transaction.telegram_message }
    after_transition :pending => :executed, :do => :update_state
    after_transition [:pending, :executed] => :closed, :do => :update_state
    after_transition [:pending, :executed, :closed] => :error, :do => :update_state
    # after_transition :executed => :closed, :do => :break_even
    # after_transition [:executed, :ordered] => :pending, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :close do
      transition [:pending, :executed] => :closed
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
        self.telegram_message(:OPEN)
        self.restrict_magic_number?
      end
    end

    state :closed do
      def update_state(state)
        self.telegram_message(:CLOSED)
        self.order.close
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

  def set_slaves_attributes(lot=nil, take_profit=nil, stop_loss=nil)
    self.slaves.each{|s| s.set_sl_and_tp_order(lot, take_profit, stop_loss)}
  end

  def set_lot_sl_tp(order_params)
    attributes = {lot: order_params["volume"], take_profit: order_params['take_profit'].to_f, stop_loss:order_params['stop_loss'].to_f}
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
    unless self.account.magics_accept.blank?
      unless account.magics_accept.try(:split).try(:include?, magic_number)
        # binding.pry
        loggings.create(content:"Account #{account.name} Magic Number Resstrict ##{magic_number}", changeset: versions.last.changeset, version:version, state: 'ERROR')
        self.erro!
      end
    end
  end

  def validate_restriction
    # restrict_nil_instrument? 
    # restrict_symbol?
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