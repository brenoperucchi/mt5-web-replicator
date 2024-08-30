require 'telegram/bot'

class Transaction < ApplicationRecord
  include Telegram::Util

  # attr_accessor :mfe, :mae, :time_trader

  has_paper_trail 
  # versions: {
  #   class_name: 'Track'
  # }

  # belongs_to :order, optional:true
  belongs_to :message, class_name: 'Message::Message', foreign_key: :message_id, optional:true
  belongs_to :account, optional:true
  belongs_to :trace, optional:true
  belongs_to :deal, optional:true

  has_many :loggings, as: :resourceable, dependent: :destroy
  
  has_many :order_transactions, dependent: :destroy
  has_many :orders, through: :order_transactions, source: :order, dependent: :destroy
  # has_many :orders

  has_many :slaves,   through: :orders,    source: :slaves
  has_many :accounts, through: :orders,    source: :accounts

  has_many :statistics, as: :statisticable, dependent: :destroy
  has_one :mfe, -> { where(kind: 'mfe') }, class_name: 'Statistic', as: :statisticable

  validates_uniqueness_of :ticket, scope: [:account_id, :trace_id], on: :create, if: Proc.new { account.try(:hedging?) }

  # enum state: { pending: 0, executed: 1, closed: 2, error: 3 }

  scope :pending,               ->{where(state: :pending)}
  scope :ordered,               ->{where(state: [:pending, :executed])}
  scope :closed,                ->{where(state: :closed)}
  scope :executed_closed,       ->{where(state: [:closed, :executed])}
  scope :finish,                ->{where(state: [:closed, 'error'])}
  scope :executed,              ->{where(state: 'executed')}
  scope :not_executed,          ->{where.not(state: 'executed')}
  scope :error,                 ->{where(state: 'error')}
  scope :not_error,             ->{where.not(state: 'error')}
  scope :closed_error,          ->{where(state: [:closed, 'error'])}
  scope :not_closed,            ->{where.not(state: [:closed, 'error'])}
  scope :buy,                   ->{where(ordertype: 0)}
  scope :sell,                  ->{where(ordertype: 1)}
  scope :gain,                  ->{where('transactions.profit >= 0')}
  scope :loss,                  ->{where('transactions.profit < 0')}

  scope :pending_executed,  ->{where(state: [:pending, :executed])}

  # before_create :set_symbol
  after_create  :validate_restriction
  # validate :restrict_symbol?, :restrict_nil_instrument?, on: :create


  class << self
    def ransackable_scopes(_auth_object = nil)
      %i[profit_search ticket_search state_search]
    end
  end

  def self.profit_search(value)
    self.where(profit:0..value.to_f)
  end

  def self.ticket_search(value)
    self.where("CAST(ticket as TEXT) ILIKE ?", "%#{value}%")
  end

  def self.state_search(*attrs)
    attrs.reject!{|item| item.empty?}
    return true unless attrs.present?
    self.where(state:attrs)
    
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
    event :erro do
      transition [:pending, :executed, :closed] => :error
    end
    event :close do
      transition [:pending, :executed] => :closed
    end
    event :restart do
      transition [:executed, :error, :closed] => :pending
    end
    
    state :error do
      def update_state(state)
        self.orders.map(&:erro)
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
        self.slaves.not_deleted.map(&:remove)
        self.orders.map(&:close)
        return true
      end
    end
  end

  def telegram_message(state)
    chat_id = self.account.store.telegram_bot_chat_id
    if chat_id.present?
      content = self.telegram_message_prepare(state)
      TelegramJob.perform_async(chat_id, content)
    end
  end

  def update_modify_meta(serializer)
    attributes = {
      lot: serializer.lot,
      take_profit: serializer.take_profit,
      stop_loss: serializer.stop_loss,
      profit: serializer.profit,
      price_request: serializer.price_open
    }
    self.assign_attributes(attributes)

    if not self.error?
      if self.changed?
        chat_id = self.account.store.telegram_bot_chat_id
        if chat_id.present?
          content = self.telegram_message_prepare(:MODIFY)
          TelegramJob.perform_async(chat_id, content)
        end

        # if self.save
        #   loggings.create(content: serializer.obj, changeset: versions.last.changeset, version: version, state: 'MODIFY')
        #   update_slaves(lot, take_profit, stop_loss)
        # end
      end
    end

    # Atualizar as estatísticas MFE e MAE independentemente das mudanças em outros atributos
    # update_mfe_mae(serializer.mfe, serializer.mae, serializer.time_trader)

    return self.save
  end

  def close_slaves
    slaves.each do |slave|
      if slave.close
        slave.loggings.create(content: "Automatically remove by Transaction.close_slaves - #{self.id}", state: "REMOVE", account: slave.account, changeset: slave.try(:versions).try(:last).try(:changeset), parent:slave.loggings.first, loggerable: slave.order.messages.last)
      end
    end
  end


  def update_slaves(lot=nil, take_profit=nil, stop_loss=nil, price_request=nil)
    self.slaves.each{|s| s.set_sl_and_tp_order(lot, take_profit, stop_loss, price_request)}
  end

  def update_mfe_mae(mfe, mae, time_trader)
    unless time_trader.nil? or mae.nil? or mfe.nil?
      # date_today = month.nil? ? DateTime.current : DateTime.current + eval(month)
      statistic_name = "#{time_trader.to_date.strftime("%Y-%m-%d")}"
      
      statistic = self.statistics.find_or_create_by(name: statistic_name, kind: :mfe)
      statistic.update(amount: mfe.to_f) if mfe.to_f > statistic.amount.to_f 

      statistic = self.statistics.find_or_create_by(name: statistic_name, kind: :mae)
      statistic.update(amount: mae.to_f) if mae.to_f < statistic.amount.to_f 
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
    read_attribute(:profit).nil? ? 0 : read_attribute(:profit).to_f
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
    restrict_magic_number(self) or trace.restrict_magic_number(self)
  end

  def restrict_magic_number(resource)
    unless resource.account.magics_accept.blank?
      trace_magic_number = self.try(:trace).try(:name_id)
      magic_numbers = Order.magic_numbers_split(resource.account.magics_accept)
      changeset = resource.try(:versions).try(:last).try(:changeset)
      version = resource.try(:version)
      unless magic_numbers.detect{|x| x == resource.magic_number}
        resource.loggings.create(content:"#{resource.class.name} ##{resource.id} has magic number #{resource.magic_number} and the account: #{resource.try(:account).try(:name)} only accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR', parent:message)
        resource.erro!
      end
    end
    resource.error?
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

  def mfe_max
     self.statistics.mfe_max.try(:amount).to_f
  end
  
  def mae_min
     self.statistics.mae_min.try(:amount).to_f
  end

  def mfe_created_at
     self.statistics.mfe_max.try(:created_at)
  end
  
  def mae_created_at
     self.statistics.mae_min.try(:created_at)
  end

end