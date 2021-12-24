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
    s_first = slaves.first 
    slaves.not_closed.each do |slave|
      if slave.id != s_first.id
        slave.update(state: "closed")
      else
        comment = "#{order.trace.id}-#{self.id}-#{slave.id}"
        slave.attribute(comment: comment)
        slave.remove
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

  def self.create_transactions(message, i)
    transaction = self.create(message.serializer.transaction_attributes(i))
    attributes_serializer = APITransactionSerializer.new(transaction.message.content).api_attributes
    transaction.slaves.create(attributes_serializer.merge(state:'pending', ticket:nil, price_request:transaction.price_request))
    transaction.execute 
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

end