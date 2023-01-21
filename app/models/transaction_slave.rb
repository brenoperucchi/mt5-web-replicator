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
  belongs_to :order
  belongs_to :master, :class_name => "Transaction", :foreign_key => "transaction_id", optional: true
  
  has_many :loggings, as: :loggerable, dependent: :destroy  
  has_many :transactions, through: :order,    source: :slaves
  has_many :accounts,     through: :order,    source: :slaves
  
  scope :to_pending,   ->{where(state: 'pending')}
  scope :to_remove,  ->{where(state: 'remove')}
  scope :pending_executed,    ->{where(state: [:pending, :executed])}
  scope :closed_deleted,      ->{where(state: [:closed, :deleted])}
  scope :opened,              ->{where(state: [:pending, :executed, :remove])}
  scope :entire,              ->{where(state: [:pending, :executed, :remove, :deleted, :closed])}
  scope :not_closed,          ->{where.not(state: ['closed', 'deleted'])}
  scope :closed_error,        ->{where(state: ['closed', 'error'])}
  scope :not_error,           ->{where.not(state: ['error'])}
  scope :not_gain,            ->{where.not('transaction_slaves.profit >= 0')}
  scope :gain,  ->{where('transaction_slaves.profit >= 0')}
  scope :loss,  ->{where('transaction_slaves.profit < 0')}
  scope :buy,   ->{where(ordertype: 0)}
  scope :sell,  ->{where(ordertype: 1)}

  validates_presence_of :symbol
  validates_uniqueness_of :ticket_master, scope: [:account_id, :transaction_id], if: Proc.new { account.hedging? }
  validates_uniqueness_of :ticket_slave,  scope: [:account_id, :transaction_id], allow_blank: true, allow_nil: true, if: Proc.new { account.hedging? }

  after_create :restrict_magic_number?

  def profit
    read_attribute(:profit).nil? ? 0 : read_attribute(:profit)
  end

  state_machine :initial => :pending do
    # after_transition :pending => any - :pending, :do => :update_state
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
        # self.master.close
      end
    end
    
    state :closed do
      def update_state(state)
        self.update(closed_at: Time.zone.now)

        self.order.close
        # self.orders.map(&:close)# if orders.first.slaves.closed.count == orders.first.slaves.count

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

  def restrict_magic_number?
    order.restrict_magic_number(self)
    # unless self.account.magics_accept.blank?
    #   magic_numbers = account.magics_accept.try(:split).try(:flatten)
    #   unless magic_numbers.try(:include?, magicnumber)
    #     loggings.create(content:"Account #{account.name} Magic Number Restrict #{magicnumber} Account only accept #{magic_numbers}", changeset: nil, version:version, state: 'ERROR')
    #     self.erro!
    #   end
    # end
  end

  def set_sl_and_tp_order(lot=nil, take_profit=nil, stop_loss=nil)
    attributes = {lot: lot, take_profit:take_profit, stop_loss:stop_loss}.compact
    self.update(attributes)
  end

  def api_request_attributes
    magicnumber = self.try(:trace).try(:name_id)
    deal_ticket = self.ticket_deal.blank? ? 0 : self.ticket_deal
    openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
    order_trace = self.trace_id
    "#{ordertype}|#{ticket_master}|#{ticket_slave}|#{order_trace}|#{self.id}|#{magicnumber}|#{master.id}|#{openprice}|#{lot}|#{stop_loss}|#{take_profit}|#{state}|#{symbol}|#{deal_ticket}|#{seconds_ago}|#{comment}|#{openat}"
  end

  def seconds_ago
    difference = (self.master.created_at - self.open_at).to_i
    difference = difference > 1 ? difference : 0
    seconds_ago = (self.master.open_at - Time.zone.now + difference).to_i.abs
    Rails.env.test? ? 0 : seconds_ago
  end

  private

  def openat
    Rails.env.test? ? 0 : self.open_at.to_i
  end

end