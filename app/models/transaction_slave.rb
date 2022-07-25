class TransactionSlave < ApplicationRecord

  ENUMS = %w(state)
  include LibEnums

  StateMachine::Machine.ignore_method_conflicts = true

  has_paper_trail 
  # versions: {
  #   class_name: 'Track'
  # }
    
  enum state: {pending:0, executed:1, remove:2, closed:3, deleted:4, error:5, disabled:6}

  belongs_to :account
  belongs_to :trace
  belongs_to :deal, optional:true
  belongs_to :master, :class_name => "Transaction", :foreign_key => "transaction_id", optional: true
  
  has_many :loggings, as: :loggerable, dependent: :destroy  
  has_many :balances, foreign_key: 'slave_id'
  has_many :orders,   through: :balances, source: :order
  has_many :accounts, through: :orders, source: :accounts
  # has_many :slaves,   through: :balances, source: :slave

  
  scope :to_pending,   ->{where(state: 'pending')}
  # scope :executed,  ->{where(state: 'executed')}
  scope :to_remove,  ->{where(state: 'remove')}
  # scope :closed,  ->{where(state: 'closed')}
  # scope :deleted,  ->{where(state: 'deleted')}
  # scope :error,  ->{where(state: 'error')}
  scope :opened,    ->{where(state: [:pending, :executed, :remove])}
  scope :entire,    ->{where(state: [:pending, :executed, :remove, :deleted, :closed])}
  scope :not_closed,  ->{where.not(state: ['closed', 'deleted'])}
  scope :closed_error,  ->{where(state: ['closed', 'error'])}
  scope :not_error,  ->{where.not(state: ['error'])}
  scope :not_gain,  ->{where.not('transaction_slaves.profit >= 0')}
  scope :gain,  ->{where('transaction_slaves.profit >= 0')}
  scope :loss,  ->{where('transaction_slaves.profit < 0')}
  scope :buy,   ->{where(ordertype: 0)}
  scope :sell,  ->{where(ordertype: 1)}
  # scope :tracer, ->{where("transaction_slaves.trace_id = ?", trace.id)} 



  validates_presence_of :symbol
  validates_uniqueness_of :ticket_master, scope: [:account_id, :transaction_id], if: Proc.new { account.hedging? }
  validates_uniqueness_of :ticket_slave,  scope: [:account_id, :transaction_id], allow_blank: true, allow_nil: true, if: Proc.new { account.hedging? }


  def profit
    read_attribute(:profit).nil? ? 0 : read_attribute(:profit)
  end

  state_machine :initial => :pending do
    after_transition [:remove,  :executed]            => :closed, :do => :update_state
    after_transition [:pending]                       => :remove, :do => :delete_pending
    # after_transition [:pending, :remove, :executed]   => :error,   :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :remove do
      transition [:error, :pending, :executed] => :remove
    end  
    event :close do
      transition [:remove, :executed] => :closed
    end  
    event :deleted do
      transition [:pending, :remove, :executed] => :deleted
    end
    event :erro do
      transition [:pending, :remove, :executed, :closed] => :error
    end

    state :remove do
      def delete_pending(state)
        self.deleted
        self.master.close
      end
    end
    
    state :closed do
      def update_state(state)
        self.update(closed_at: Time.zone.now)

        # if master.trace.copy? and account.hedging?
        #   master.close
        # elsif master.slaves.count > 1 and master.slaves.first == self

        # NOTE - IF TP1 IS REACH THEN TPs IS MASTER OPEN PRICE
        if master.slaves.count > 1 and master.slaves.first == self
          master.slaves.not_closed.each do |slave|
            slave.update(stop_loss: slave.price_open)
          end
        # else
        #   master.close if master.slaves.not_closed.count == 0
        end
      end
    end
   
    # state :error do
    #   def update_state(state)
    #     # if master.trace.copy? 
    #       if account.hedging?
    #         master.erro
    #       elsif master.slaves.not_error.not_closed.count == 0
    #         master.erro
    #       end
    #     # end
    #   end    
    # end

  end

  def set_sl_and_tp_order(take_profit=nil, stop_loss=nil)
    attributes = {take_profit:take_profit, stop_loss:stop_loss}.compact
    self.update(attributes)
  end

  def api_request_attributes
    deal_ticket = self.ticket_deal.blank? ? 0 : self.ticket_deal
    openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
    order_trace = self.trace_id
    msg = "#{ordertype}|#{ticket_master}|#{ticket_slave}|#{order_trace}|#{self.id}|#{self.magic_number}|#{master.id}|#{openprice}|#{lot}|#{stop_loss}|#{take_profit}|#{state}|#{symbol}|#{deal_ticket}|#{seconds_ago}|#{comment}"
    return msg
  end

  private

  def seconds_ago
    seconds_ago = (self.master.open_at - Time.zone.now).to_i.abs
    Rails.env.test? ? 0 : seconds_ago
  end

end