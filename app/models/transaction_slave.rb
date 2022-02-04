class TransactionSlave < ApplicationRecord

  StateMachine::Machine.ignore_method_conflicts = true
    
  enum state: {pending:0, executed:1, remove:2, closed:3, deleted:4, error:5, disabled:6}

  belongs_to :account
  belongs_to :master, :class_name => "Transaction", :foreign_key => "transaction_id"
  
  has_many :loggings, as: :loggerable, dependent: :destroy  
  
  scope :to_pending,   ->{where(state: 'pending')}
  # scope :executed,  ->{where(state: 'executed')}
  scope :to_remove,  ->{where(state: 'remove')}
  # scope :closed,  ->{where(state: 'closed')}
  # scope :deleted,  ->{where(state: 'deleted')}
  # scope :error,  ->{where(state: 'error')}
  scope :opened,    ->{where(state: [:pending, :executed, :remove])}
  scope :entire,    ->{where(state: [:pending, :executed, :remove, :deleted, :closed])}
  scope :not_closed,  ->{where.not(state: ['closed', 'deleted'])}
  scope :not_error,  ->{where.not(state: ['error'])}

  validates_presence_of :symbol


  state_machine :initial => :pending do
    after_transition [:remove, :executed] => :closed, :do => :update_state
    after_transition [:pending, :executed] => :erro, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :remove do
      transition [:pending, :executed] => :remove
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
        self.update(closed_at: Time.zone.now)

        if master.trace.copy? and account.hedging?
          master.close
        elsif master.slaves.count > 1 and master.slaves.first == self
          master.slaves.not_closed.each do |slave|
            slave.update(stop_loss: slave.price_open)
          end
        else
          master.close if master.slaves.not_closed.count == 0
        end
      end
    end
   
    state :erro do
      def update_state(state)
        if master.trace.copy? 
          if account.hedging?
            master.erro
          elsif master.slaves.not_error.not_closed.count == 0
            master.erro
          end
        end
      end
    end
  end

  def set_sl_and_tp_order(take_profit=nil, stop_loss=nil)
    attributes = {take_profit:take_profit, stop_loss:stop_loss}.compact
    self.update(attributes)
  end

  def api_request_attributes
    deal_ticket = self.ticket_deal.blank? ? 0 : self.ticket_deal
    seconds_ago = (self.created_at - Time.zone.now).to_i.abs
    openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
    msg = "#{ordertype}|#{ticket_master}|#{ticket_slave}|#{master.trace.id}|#{self.id}|#{self.magic_number}|#{master.id}|#{openprice}|#{lot}|#{stop_loss}|#{take_profit}|#{state}|#{symbol}|#{deal_ticket}|#{seconds_ago}|#{comment}"
    return msg
  end

end