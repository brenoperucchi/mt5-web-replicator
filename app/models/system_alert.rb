class SystemAlert < ApplicationRecord
  # Relacionamentos polimórficos para permitir associar alertas a diferentes tipos de objetos
  belongs_to :alertable, polymorphic: true, optional: true

  # Enums para status e severidade
  enum status: { active: 'active', in_progress: 'in_progress', resolved: 'resolved', ignored: 'ignored' }
  enum severity: { info: 'info', warning: 'warning', error: 'error', critical: 'critical' }

  # Escopos
  scope :unresolved, -> { where(status: ['active', 'in_progress']) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_source, ->(source) { where(source: source) }
  scope :orphaned_transactions, -> { where(source: 'transaction', message: 'Orphaned transaction detected') }
  
  # Validações
  validates :message, presence: true
  validates :severity, presence: true
  validates :status, presence: true
  
  # Callbacks
  before_validation :set_default_status, on: :create
  
  # Métodos de classe para criar alertas específicos
  class << self
    # Cria um alerta para transação órfã (sem associação orders)
    def create_orphaned_transaction_alert(transaction)
      create(
        message: 'Orphaned transaction detected',
        severity: 'warning',
        source: 'transaction',
        source_id: transaction.id,
        alertable: transaction,
        details: {
          account_id: transaction.account_id,
          trace_id: transaction.trace_id,
          profit: transaction.profit,
          symbol: transaction.symbol,
          ticket: transaction.ticket
        }
      )
    end
    
    # Cria um alerta para falha de replicação de ordens
    def create_replication_failure_alert(order, error_message)
      create(
        message: 'Order replication failure',
        severity: 'error',
        source: 'order',
        source_id: order.id,
        alertable: order,
        details: {
          account_id: order.account_id,
          trace_id: order.trace_id,
          error: error_message
        }
      )
    end
    
    # Cria um alerta para discrepância de cálculos
    def create_calculation_discrepancy_alert(account, details)
      create(
        message: 'Calculation discrepancy detected',
        severity: 'warning',
        source: 'account',
        source_id: account.id,
        alertable: account,
        details: details
      )
    end
  end

  # Método para marcar como resolvido
  def resolve!(resolution_notes = nil)
    update(
      status: 'resolved',
      resolved_at: Time.current,
      details: details.merge(resolution_notes: resolution_notes)
    )
  end
  
  # Método para marcar como ignorado
  def ignore!(reason = nil)
    update(
      status: 'ignored',
      details: details.merge(ignore_reason: reason)
    )
  end
  
  private
  
  def set_default_status
    self.status ||= 'active'
    self.details ||= {}
  end
end
