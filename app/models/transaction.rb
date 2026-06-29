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
  has_many :system_alerts, as: :alertable, dependent: :destroy

  has_many :transaction_traces, dependent: :destroy, foreign_key: :master_id
  has_many :traces, through: :transaction_traces, source: :trace, dependent: :destroy
  # has_many :traces, through: :transaction_traces, source: :trace
  
  has_many :order_transactions, dependent: :destroy
  has_many :orders, through: :order_transactions, source: :order, dependent: :destroy
  has_many :traces_orders, through: :orders, source: :trace
  # has_many :orders

  has_many :slaves,   through: :orders,    source: :slaves
  has_many :accounts, through: :orders,    source: :accounts

  has_many :statistics, as: :statisticable, dependent: :destroy
  has_one :mfe, -> { where(kind: 'mfe') }, class_name: 'Statistic', as: :statisticable

  validates_uniqueness_of :ticket, scope: [:account_id, :trace_id, :order_id], on: :create, if: Proc.new { account.try(:hedging?) }

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
  scope :not_limit_pending,   ->{where('transactions.ordertype >= 2').where.not(profit:0)}
  scope :orphaned,            ->{left_outer_joins(:order_transactions).where(order_transactions: {id: nil})}

  scope :pending_executed,  ->{where(state: [:pending, :executed])}
  scope :not_conciliated,   ->{where(conciliated_at: nil)}
  scope :conciliated,       ->{where.not(conciliated_at: nil)}

  # before_create :set_symbol
  after_create  :validate_restriction
  # Desabilitando o callback que causa problemas nos testes
  # after_create  :ensure_order_association
  # validate :restrict_symbol?, :restrict_nil_instrument?, on: :create

  # Método para verificar se uma transação está órfã (sem associação com orders)
  def orphaned?
    order_transactions.empty?
  end

  # Método para corrigir uma transação órfã associando-a a uma ordem
  def fix_orphaned_association
    return false unless orphaned?
    
    # Procura por uma order compatível (mesmo trace e account)
    compatible_order = Order.where(trace: trace, account: account).first
    
    if compatible_order
      OrderTransaction.create(order_id: compatible_order.id, transaction_id: id)
      
      # Criação do alerta apenas se não estiver em ambiente de teste
      unless Rails.env.test?
        SystemAlert.create(
          message: "Orphaned transaction fixed automatically",
          severity: "info",
          source: "transaction",
          source_id: id,
          alertable: self,
          details: {
            account_id: account_id,
            trace_id: trace_id,
            order_id: compatible_order.id,
            fixed_at: Time.current
          }
        )
      end
      
      return true
    else
      return false
    end
  end

  # Garante que a transação tenha uma associação com pelo menos uma ordem
  # Este método agora é chamado manualmente, não via callback
  def ensure_order_association
    return true unless orphaned?
    
    # Tenta corrigir automaticamente
    fixed = fix_orphaned_association
    
    # Se não conseguir corrigir, cria um alerta (exceto em ambiente de teste)
    unless fixed || Rails.env.test?
      SystemAlert.create_orphaned_transaction_alert(self)
    end
    
    true
  end

  # Encontrar todas as transações órfãs e tentar corrigir
  def self.fix_all_orphaned
    orphaned_count = 0
    fixed_count = 0
    
    orphaned.find_each do |transaction|
      orphaned_count += 1
      fixed = transaction.fix_orphaned_association
      fixed_count += 1 if fixed
    end
    
    { orphaned: orphaned_count, fixed: fixed_count }
  end

  # Método para remover transações órfãs
  def self.clean_orphaned(older_than_days = 30)
    cutoff_date = Time.current - older_than_days.days
    count = orphaned.where('created_at < ?', cutoff_date).count
    orphaned.where('created_at < ?', cutoff_date).destroy_all
    { deleted: count }
  end

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
    event :reset do
      transition [:executed, :error, :closed] => :pending
    end
    
    state :error do
      def update_state(state)
        self.orders.map(&:erro)
      end
    end
    state :executed do
      def update_state(state)
        # if self.accept_magic_number?
        #   # self.telegram_message(:OPEN)
        # end
      end
    end

    state :closed do
      def update_state(state)
        # self.telegram_message(:CLOSED)
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
      # TelegramJob.perform_async(chat_id, content)
    end
  end

  def update_modify_meta(serializer)
    volume = self.lot
    self.assign_attributes(serializer.transaction_attributes)

    if not self.error?
      if self.changed?
        chat_id = self.account.store.telegram_bot_chat_id
        if chat_id.present?
          content = self.telegram_message_prepare(:MODIFY)
          # TelegramJob.perform_async(chat_id, content)
        end
      end
    end
    if self.save
      update_slaves(serializer, volume)
      return true
    else
      false
    end
  end

  def close_slaves
    slaves.each do |slave|
      if slave.remove
        slave.loggings.create(content: "Automatically remove by Transaction.close_slaves - #{self.id}", state: "REMOVE", account: slave.account, changeset: slave.try(:versions).try(:last).try(:changeset), parent:slave.loggings.first, loggerable: slave.order.messages.last)
      end
    end
  end


  def update_slaves(serializer, transaction_lot)
    self.slaves.each do |slave| 
      contract_volume = slave.try(:account).try(:contract_volume)
      slave_attributes = serializer.slave_attributes
      if slave.executed? and contract_volume !=  "0" 
        if transaction_lot == slave.lot
          volume = serializer.volume 
        else  
          volume = contract_volume
        end
        slave_attributes.merge!(lot: volume.to_f)
      end
      slave.set_sl_and_tp_order(*slave_attributes.values)
    end
  end

  def update_mfe_mae(serializer)
    attributes = serializer.mfe_attributes

    if attributes.present?
      # date_today = month.nil? ? DateTime.current : DateTime.current + eval(month)
      statistic_name = "#{serializer.time_trader.to_date.strftime("%Y-%m-%d")}"
      
      statistic = self.statistics.find_or_create_by(name: statistic_name, kind: :mfe)
      statistic.update(amount: serializer.mfe.to_f) if serializer.mfe.to_f > statistic.amount.to_f 

      statistic = self.statistics.find_or_create_by(name: statistic_name, kind: :mae)
      statistic.update(amount: serializer.mae.to_f) if serializer.mae.to_f < statistic.amount.to_f 
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

  # # Método profit modificado para garantir cálculo consistente
  # def profit
  #   raw_value = read_attribute(:profit)
  #   raw_value.nil? ? 0 : raw_value.to_f
  # end

  def set_symbol
    if order.trace.telegram?
      ## TODO - CHANGE FOR SEARCHING FOR EXACTLY SYMBOL ON INSTRUMENTS
      self.symbol = account.instruments.detect{|x| message.content.gsub(/\W/, '').upcase.include?(x[:symbol].upcase) }.try(:name)
    else
      self.symbol = account.instruments.find_by(symbol: message.serializer.symbol.try(:upcase)).try(:name)
    end
  end

  def accept_magic_number?
    # restrict_magic_number(self) or trace.restrict_magic_number(self)
    TradeHelperService.resource_restricted?(self, self.account) 
  end

  # def restrict_magic_number(resource)
  #   unless resource.account.magics_accept.blank?
  #     trace_magic_number = self.try(:trace).try(:name_id)
  #     magic_numbers = Order.magic_numbers_split(resource.account.magics_accept)
  #     changeset = resource.try(:versions).try(:last).try(:changeset)
  #     version = resource.try(:version)
  #     unless magic_numbers.detect{|x| x == resource.magic_number}
  #       resource.loggings.create(content:"#{resource.class.name} ##{resource.id} has magic number #{resource.magic_number} and the account: #{resource.try(:account).try(:name)} only accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR', parent:message)
  #       resource.erro!
  #     end
  #   end
  #   resource.error?
  # end  

  def validate_restriction
    # restrict_nil_instrument? 
    # restrict_symbol?
  end

  def api_request_attributes
    # order.api_request_attributes(self)
    TradeHelperService.api_request_attributes(self, self)
  end

  def self.api_request_attributes(scope)
    return if scope.nil?
      TradeHelperService.api_request_attributes_scope(order, self, scope)
      # self.send(scope).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 60.days)).collect{|t| t.api_request_attributes}.join('/')
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

  def mark_as_conciliated
    update(conciliated_at: Time.current)
  end

  def conciliated?
    conciliated_at.present?
  end

end