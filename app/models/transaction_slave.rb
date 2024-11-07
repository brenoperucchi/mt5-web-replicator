class TransactionSlave < ApplicationRecord
  
  enum state: {pending:0, executed:1, remove:2, closed:3, deleted:4, error:5, disabled:6, conciliated:7}

  include LibEnums

  StateMachine::Machine.ignore_method_conflicts = true

  has_paper_trail 
  # versions: {
  #   class_name: 'Track'
  # }
    

  belongs_to :account
  belongs_to :trace
  belongs_to :order
  belongs_to :store, optional: true
  belongs_to :master, :class_name => "Transaction", :foreign_key => "transaction_id", optional: true
  
  has_many :loggings, as: :resourceable, dependent: :destroy  
  has_many :transactions, through: :order,    source: :slaves
  has_many :accounts,     through: :order,    source: :slaves
  
  scope :to_pending,          ->{where(state: 'pending')}
  scope :to_remove,           ->{where(state: 'remove')}
  scope :pending_executed,    ->{where(state: [:pending, :executed])}
  scope :closed_deleted,      ->{where(state: [:closed, :deleted])}
  scope :opened,              ->{where(state: [:pending, :executed, :remove])}
  scope :entire,              ->{where(state: [:pending, :executed, :remove, :deleted, :closed])}
  scope :not_closed,          ->{where.not(state: ['closed', 'deleted'])}
  scope :closed_error,        ->{where(state: ['closed', 'error'])}
  scope :not_executed,        ->{where.not(state: ['executed'])}
  scope :not_error,           ->{where.not(state: ['error'])}
  scope :not_gain,            ->{where.not('transaction_slaves.profit >= 0')}
  scope :gain,                ->{where('transaction_slaves.profit >= 0')}
  scope :loss,                ->{where('transaction_slaves.profit < 0')}
  scope :buy,                 ->{where(ordertype: 0)}
  scope :sell,                ->{where(ordertype: 1)}

  validates_presence_of :symbol
  validates_uniqueness_of :ticket_master, scope: [:account_id, :ticket_slave, :order_id], on: :create, if: Proc.new { account.try(:hedging?) }
  validates_uniqueness_of :ticket_slave,  scope: [:account_id, :transaction_id, :order_id], on: :create, allow_blank: false, allow_nil: false, 
                          if: Proc.new { account.try(:hedging?) }, unless: Proc.new { ticket_slave == 0}
  # validates_uniqueness_of :ticket_master, scope: [:account_id, :transaction_id], on: :create, if: Proc.new { account.try(:hedging?) }

  after_create :restrict_magic_number?#, :check_duplicate


  class << self
    def ransackable_scopes(_auth_object = nil)
      %i[profit_search ticker_master_search ticket_slave_search state_search]
    end
  end


  def self.profit_search(value)
    self.where(profit:0..value.to_f)
  end

  def self.ticket_slave_search(value)
    self.where("CAST(ticket_slave as TEXT) ILIKE ?", "%#{value}%")
  end

  def self.ticker_master_search(value)
    self.where("CAST(ticket_master as TEXT) ILIKE ?", "%#{value}%")
  end

  def self.state_search(*attrs)
    attrs.reject!{|item| item.empty?}
    return true unless attrs.present?
    self.where(state:attrs)    
  end

  def open_at_master
    master.try(:open_at)
  end

  def closed_at_master
    master.try(:closed_at)
  end

  # def check_duplicate
  #   self.class.check_duplicate(self.ticket_master, self.account)
  # end

  # def self.check_duplicate(ticket, account)
  #   slaves = self.where(ticket_master: ticket, account: account)
  #   # execute_slaves = self.where(ticket_master: ticket, account: account, state: [:closed, :executed]).where.not(ticket_slave: nil)
  #   if slaves.count > 1 and slaves.pending.count > 0
  #       slave = slaves.pending.last
  #       slave.deleted
  #       slave.loggings.create(content:"Slave ID #{slave.id} - Account #{account.name} Duplicate", changeset: slave.try(:versions).try(:last).try(:changeset), version:slave.versions.last, state: 'ERROR', loggerable: slave.order.message, parent:slave.master.loggings.first.parent)
  #       slave.order.erro
  #   end
  # end

  def profit
    read_attribute(:profit).nil? ? 0 : read_attribute(:profit)
  end

  state_machine :initial => :pending do
    after_transition [:remove,  :executed]            => :closed, :do => :update_state

    event :execute do
      transition [:error, :pending] => :executed
    end
    event :remove do
      transition [:error, :pending, :executed, :closed] => :remove
    end  
    event :close do
      transition [:pending, :remove, :executed, :error] => :closed
    end  
    event :conciliate do
      transition [:pending, :remove, :executed, :error] => :conciliated
    end  
    event :deleted do
      transition [:pending, :remove, :executed, :closed] => :deleted
    end
    event :erro do
      transition [:pending, :remove, :executed, :closed] => :error
    end
    
    state :closed do
      def update_state(state)
        self.update(closed_at: Time.zone.now)
        self.order.close
      end
    end
    
  end

  def restrict_magic_number?
    order.restrict_magic_number(self)
  end

  def set_sl_and_tp_order(take_profit, stop_loss, price_request, lot)
    attributes = {take_profit: take_profit, stop_loss: stop_loss, price_request: price_request, lot: lot}.compact
    self.update(attributes)
  end

  def api_request_attributes
    order.api_request_attributes(self)
  end

  def seconds_ago
    seconds_ago1 = 0 
    seconds_ago2 = 0

    seconds_ago1 = (self.master.open_at - Time.zone.now).to_i.abs if self.master.try(:open_at) 
    seconds_ago2 = (self.master.created_at - Time.zone.now).to_i.abs if self.master.try(:created_at)
    
    result = seconds_ago1 > seconds_ago2 ? seconds_ago1 : seconds_ago2
  end

end