class TransactionSlave < ApplicationRecord
    
  enum state: {pending:0, executed:1, remove:2, closed:3, deleted:4, error:5}

  belongs_to :account
  belongs_to :master, :class_name => "Transaction", :foreign_key => "transaction_id"
  
  has_many :loggings, as: :loggerable, dependent: :destroy  
  
  # scope :pending,   ->{where(state: 'pending')}
  # scope :executed,  ->{where(state: 'executed')}
  # scope :remove,  ->{where(state: 'remove')}
  # scope :closed,  ->{where(state: 'closed')}
  # scope :deleted,  ->{where(state: 'deleted')}
  # scope :error,  ->{where(state: 'error')}
  scope :opened,    ->{where(state: [:pending, :executed])}
  scope :entire,    ->{where(state: [:pending, :executed, :remove, :deleted, :closed])}
  scope :not_closed,  ->{where.not(state: ['closed', 'deleted'])}

  validates_presence_of :symbol


  state_machine :initial => :pending do
    after_transition :executed => :closed, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :remove do
      transition :executed => :remove
    end  
    event :close do
      transition [:remove, :executed] => :closed
    end  
    event :deleted do
      transition [:pending, :executed] => :deleted
    end
    event :erro do
      transition [:pending, :executed, :closed] => :error
    end
    state :closed do
      def update_state(state)
        if master.slaves.count > 1 and master.slaves.first == self
          master.slaves.not_closed.each do |slave|
            slave.update(stop_loss: slave.price_open)# unless meta_get_closed_ticket_position(self.order.trace, transc.ticket)          
          end
        end
        master.close if master.slaves.not_closed.count == 0
      end
    end


  end

  # def meta_attributes(value=0)
  #   openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
  #   instrument = master.order.trace.instruments.find_by_symbol(symbol)
  #   @meta_attributes = { 
  #     instrument: symbol,
  #     ordertype: ordertype,
  #     volume:self.lot,
  #     openprice: openprice,
  #     slippage:10,
  #     magic_number: self.magic_number.to_i.abs,
  #     stoploss: stop_loss,
  #     takeprofit: take_profit,
  #     trace_id: master.order.trace.id,
  #     transaction_id: self.id,
  #     ticket: self.ticket,
  #     ticket_deal: self.ticket_deal,
  #   }
  # end

  def api_request_attributes
    # Rails.logger.debug "ACCOUNT => #{self.account.name}"
    deal_ticket = self.ticket_deal.blank? ? 0 : self.ticket_deal
    seconds_ago = (self.created_at - Time.zone.now).to_i.abs
    # instrument = master.order.trace.instruments.find_by_symbol(symbol)
    openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
    msg = "#{ordertype}|#{ticket}|#{master.try(:order).try(:trace).try(:id)}|#{self.id}|#{self.magic_number}|#{master.id}|#{openprice}|#{lot}|#{stop_loss}|#{take_profit}|#{state}|#{symbol}|#{deal_ticket}|#{seconds_ago}|"
    return msg
  end

end