class Transaction < ApplicationRecord

  belongs_to :order
  belongs_to :message
  belongs_to :account

  has_many :loggings, as: :loggerable, dependent: :destroy
  has_many :slaves, :class_name => "TransactionSlave", :foreign_key => "transaction_id", dependent: :destroy

  scope :closed,      ->{where(state: 'closed')}
  scope :finish,      ->{where(state: ['closed', 'error'])}
  scope :executed,    ->{where(state: 'executed')}
  scope :not_closed,  ->{where.not(state: ['closed', 'error'])}

  before_create :set_symbol
  after_create  :validate_restriction
  # validate :restrict_symbol?, :restrict_nil_instrument?, on: :create

  state_machine :initial => :pending do
    after_transition :pending => :executed, :do => :update_state
    after_transition :pending => :executed, :do => :update_state
    after_transition :executed => :closed, :do => :update_state
    # after_transition :executed => :closed, :do => :break_even
    after_transition [:pending, :executed, :closed] => :error, :do => :update_state
    # after_transition [:executed, :ordered] => :pending, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :close do
      transition :executed => :closed
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
        self.order.execute
      end
    end
    state :closed do
      def update_state(state)
        self.order.close
        self.update(close_at: Time.current, profit: slaves.sum(:profit))
      end
    end
  end

  def close_order
    slaves.not_closed.each do |slave|
      slave.remove
    end
  end


  def close_copy
    # last = slaves.last
    slaves.not_closed.each do |slave|
      # if slave.id != slaves.first.id
      #   slave.update(state: "closed")
      if slave.id == slaves.first.id
        # comment = "#{order.trace.id}-#{self.id}-#{last.id}"
        # slave.attributes = {comment: comment}
        slave.remove
      else
        slave.update(state: "closed")
      end
    end
    
  end

  def set_all_sl_and_tp_order(take_profit=nil, stop_loss=nil)
    self.slaves.each{|s| s.set_sl_and_tp_order(take_profit, stop_loss)}
  end

  # def copy_attributes(value=0)
  #   # openprice = (type.include?('limit') or type.include?('stop')) ? price_request : 0
  #   openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
  #   instrument = order.trace.instruments.find_by_symbol(symbol)
  #   @meta_attributes = { 
  #     instrument: symbol,
  #     ordertype: ordertype,
  #     volume:self.lot,
  #     openprice: openprice,
  #     slippage:10,
  #     magic_number: self.magic_number.to_i.abs,
  #     stoploss: stop_loss,
  #     takeprofit: take_profit,
  #     trace_id: order.trace.id,
  #     transaction_id: self.id,
  #     ticket: self.ticket
  #   }
  # end

  # def self.create_transactions(message, i)
  #   transaction = self.create(message.serializer.transaction_attributes(i).merge(lot: account.instrument_volume(i))
  #   attributes_serializer = APITransactionSerializer.new(transaction.message.content).api_attributes
  #   transaction.slaves.create(attributes_serializer.merge(state:'pending', ticket:nil, price_request:transaction.price_request))
  #   transaction.execute 
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


  def self.remove(id)
    TransactionSlave.find(id).update(state: :remove)
    TransactionSlave.find(id).master.update(state: :executed)  
  end

  def set_symbol
    if order.trace.telegram?
      ## TODO - CHANGE FOR SEARCHING FOR EXACTLY SYMBOL ON INSTRUMENTS
      self.symbol = account.instruments.detect{|x| message.content.gsub(/\W/, '').upcase.include?(x[:symbol].upcase) }.try(:name)
    else
      self.symbol = account.instruments.find_by(symbol: message.serializer.symbol.try(:upcase)).try(:name)
    end
  end

  def validate_restriction
    restrict_nil_instrument? 
    restrict_symbol?
  end


  def restrict_nil_instrument?
    if symbol.nil?
        self.response = "Restrict Instrument"
        # errors.add(:symbol, "instrument nil")
        self.erro!
      end   
  end

  def restrict_symbol?
    if message.store.tag_list.map(&:downcase).include?(symbol.try(:downcase))
        self.response = "Restrict Symbol"
        # errors.add(:symbol, "store restrict symbol")
        self.erro!
      end
  end


end