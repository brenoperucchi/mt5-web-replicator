# require "#{Rails.root}/lib/telegram/signal"
class Transaction < ApplicationRecord

  belongs_to :order
  belongs_to :message

  # has_many :morphics#, as: :morphicable     
  # has_many :accounts, :through => :morphics, :source => :account
  has_many :transaction_slaves, :class_name => "TransactionSlave", :foreign_key => "transaction_id", dependent: :destroy
  
  has_one :morphic#, as: :morphicable     
  has_one :account, :through => :morphic, :source => :account
  
  has_many :loggings, as: :loggerable

  scope :closed, ->{where(state: 'closed')}
  scope :not_closed, ->{where.not(state: ['closed', 'error'])}
  scope :finish, ->{where(state: ['closed', 'error'])}
  scope :executed, ->{where(state: 'executed')}

  state_machine :initial => :pending do
    after_transition :pending => :executed, :do => :update_state
    after_transition :pending => :executed, :do => :update_state
    after_transition :executed => :closed, :do => :update_state
    after_transition :executed => :closed, :do => :break_even
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
      	# meta_get_open_positions(self, self.order.trace)
      end


    end
    state :closed do
      def break_even(state)
        if order.transactions.count > 1 and first_transaction?
          order.transactions.not_closed.each do |transc|
            # order.transactions.where.not(id: order.transactions.finish.map(&:id)).each do |transc|
            t_slave = transc.transaction_slaves.last 
            transc.set_sl_and_tp_order(take_profit=t_slave.take_profit, stop_loss=t_slave.price_open)# unless meta_get_closed_ticket_position(self.order.trace, transc.ticket)
            # transc.update(stop_loss: transc.price_open)# if transc.response_error != 10009 
          end
        end
      end

      def update_state(state)
        self.order.close
        self.update(close_at: DateTime.now)
      end
    end
  end

  def first_transaction?
  	order.transactions.first == self
  end

  def close_order
    if self.close
      self.order.slaves.not_closed.each do |slave|
        slave.ticket.nil? ? slave.update(state: 'deleted') : slave.update(state: 'remove') 
      end
    end
  end

  def set_sl_and_tp_order(take_profit=nil, stop_loss=nil)
    attributes = {take_profit:take_profit, stop_loss:stop_loss}.compact
    self.update(attributes)
    self.transaction_slaves.update_all(attributes)
  end

  def meta_attributes(value=0)
    # openprice = (type.include?('limit') or type.include?('stop')) ? price_request : 0
    openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
    instrument = order.trace.instruments.find_by_symbol(symbol)
    @meta_attributes = { 
      instrument: symbol,
      ordertype: ordertype,
      volume:self.lot,
      openprice: openprice,
      slippage:10,
      magic_number: self.magic_number.to_i.abs,
      stoploss: stop_loss,
      takeprofit: take_profit,
      trace_id: order.trace.id,
      transaction_id: self.id,
      ticket: self.ticket
    }
  end

  # def self.create_transactions(message, i)
  #   transaction = self.create(message.serializer.transaction_attributes(i))
  #   binding.pry
  #   attributes_serializer = APITransactionSerializer.new(transaction.message.content).api_attributes
  #   transaction.transaction_slaves.create(attributes_serializer.merge(state:'pending', ticket:nil, price_request:transaction.price_request))
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

end