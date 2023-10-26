class TransactionSlave < ApplicationRecord

  ENUMS = %w(state)
  include LibEnums

  StateMachine::Machine.ignore_method_conflicts = true

  has_paper_trail 
  # versions: {
  #   class_name: 'Track'
  # }
    
  enum state: {pending:0, executed:1, remove:2, closed:3, deleted:4, error:5, disabled:6, closed_info:7}

  belongs_to :account
  belongs_to :trace
  belongs_to :order
  belongs_to :master, :class_name => "Transaction", :foreign_key => "transaction_id", optional: true
  
  has_many :loggings, as: :resourceable, dependent: :destroy  
  has_many :transactions, through: :order,    source: :slaves
  has_many :accounts,     through: :order,    source: :slaves
  
  scope :to_pending,   ->{where(state: 'pending')}
  scope :to_remove,  ->{where(state: 'remove')}
  scope :pending_executed,    ->{where(state: [:pending, :executed])}
  scope :closed_deleted,      ->{where(state: [:closed, :deleted])}
  scope :opened,              ->{where(state: [:pending, :executed, :remove, :closed_info])}
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
  validates_uniqueness_of :ticket_master, scope: [:account_id], on: :create, if: Proc.new { account.try(:hedging?) }
  validates_uniqueness_of :ticket_slave,  scope: [:account_id, :transaction_id], on: :create, allow_blank: false, allow_nil: false, 
                            if: Proc.new { account.try(:hedging?) }
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
    master.open_at
  end

  def closed_at_master
    master.closed_at
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
    # after_transition :pending => any - :pending, :do => :update_state
    after_transition [:remove,  :executed]            => :closed, :do => :update_state
    after_transition [:pending]                       => :remove, :do => :delete_pending
    # after_transition [:pending, :remove, :executed]   => :error,   :do => :update_state

    event :execute do
      transition [:error, :pending] => :executed
    end
    event :remove do
      transition [:error, :pending, :executed] => :remove
    end  
    event :close do
      transition [:remove, :executed] => :closed
    end  
    event :deleted do
      transition [:pending, :remove, :executed, :closed] => :deleted
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
        # if master.slaves.count > 1 and master.slaves.first == self
        #   master.slaves.not_closed.each do |slave|
        #     slave.update(stop_loss: slave.price_open)
        #   end
        # # else
        # #   master.close if master.slaves.not_closed.count == 0
        # end
      end
    end
    
  end

  def restrict_magic_number?
    order.restrict_magic_number(self)
  end

  def set_sl_and_tp_order(lot=nil, take_profit=nil, stop_loss=nil)
    lot = nil if account.hedging? or master.account.hedging?
    attributes = {lot: lot, take_profit:take_profit, stop_loss:stop_loss}.compact
    self.update(attributes)
  end

  def api_request_attributes
    order.api_request_attributes(self)
  end

  def seconds_ago
    difference = (self.master.created_at - self.master.open_at).to_i
    difference = difference > 1 ? difference : 0
    seconds_ago = (self.master.open_at - Time.zone.now + difference).to_i.abs
    Rails.env.test? ? 0 : seconds_ago
  end

  # def check_account_contract_volume(value = nil)
  #   number = value || self.lot
  #   contract_volume = account.contract_volume 
  #   return self.lot if not contract_volume.present? or contract_volume.to_f <= 0.0

  #   if number.include?(".")
  #     decimal_part = number.split(".").last
  #     new_number = "0." + ("0" * (decimal_part.length-1).abs) + (1 * contract_volume.to_i).to_s
  #     return new_number
  #   else
  #     return contract_volume
  #   end
  # end


end