class TestService
  extend ApplicationHelper

  def self.check(account_id, month_year, model: :transactions, association: :transactions)
    account = Account.find(account_id)
    store_id = 1
    trace_name = "conciliated#{account.name}"

    trace = Trace.includes(:store_traces).where(name: trace_name, name_id: -1, store_traces: { store_id: store_id }).take

    trace_profit = 0.0
    trace_fee = 0.0
    trace_count = 0
    results = []
    results_print = []

    # Contadores para rastrear registros
    total_registros_method1 = 0
    total_registros_method2 = 0
    total_registros_method3 = 0
    transaction_ids_method1 = []
    transaction_ids_method2 = []
    transaction_ids_method3 = []

    # Define range based on month_year parameter
    range = if month_year
              begin
                start_date = Time.zone.parse("#{month_year}-01")
                start_date.beginning_of_month...start_date.next_month.beginning_of_month
              rescue ArgumentError, TypeError
                raise "Invalid month_year format. Use 'YYYY-MM'."
              end
            else
              nil
            end

    traces = account.public_send(association).where(account_id: account_id).map(&:trace_id)
    traces += account.traces&.pluck(:id) if traces.empty?
    trace_ids = []
    trace_trace_ids = []
    account_traces_profit = 0.0
    account_traces_fee = 0.0
    
    # Método 1: Calculando pelos traces do account (account.traces)
    puts "=== MÉTODO 1: Cálculo através de account.traces ==="
    account.traces.each do |trace|
      query = { account: account }
      query[:closed_at] = range if range
      trace_transactions = trace.public_send(association).where(query)
      
      count_trace = trace_transactions.count
      total_registros_method1 += count_trace
      transaction_ids_method1 += trace_transactions.pluck(:id)
      puts "  - Trace #{trace.id} (#{trace.name}): #{count_trace} registros"
      
      trace_profit_total = trace_transactions.sum(:profit).to_f
      trace_fee_total = trace_transactions.sum(:fee).to_f
      
      account_traces_profit += trace_profit_total
      account_traces_fee += trace_fee_total
    end
    
    puts "  Total de registros Método 1: #{total_registros_method1}"
    puts "  Total profit: #{account_traces_profit.round(2)}, Total fee: #{account_traces_fee.round(2)}"
    puts "  Total geral: #{(account_traces_profit + account_traces_fee).round(2)}"
    puts ""
    
    # Método 2: Iterando através dos trace_ids únicos (pode duplicar se trace_id estiver em account.transactions e account.traces)
    puts "=== MÉTODO 2: Cálculo através de traces.uniq (Potencial Duplicação) ==="
    traces.uniq.each do |trace_id|
      trace = Trace.find_by(id: trace_id)
      next if trace.nil?
      
      query = { account: account }
      query[:closed_at] = range if range
      associated_records = trace.public_send(association).where(query)
      
      count_trace = associated_records.count
      total_registros_method2 += count_trace
      transaction_ids_method2 += associated_records.pluck(:id)
      puts "  - Trace #{trace.id} (#{trace.name}): #{count_trace} registros"
      
      trace_profit_sum = associated_records.sum(:profit).to_f
      trace_fee_sum = associated_records.sum(:fee).to_f
      
      results << "Trace: #{trace.id} Name: #{trace.name} - Count: #{associated_records.count} - Profit: #{trace_profit_sum.round(2)} - Fee: #{trace_fee_sum.round(2)}"
      trace_profit += trace_profit_sum
      trace_fee += trace_fee_sum
      trace_count += associated_records.count
      trace_ids += associated_records&.pluck(:id)
      trace_trace_ids += associated_records&.pluck(:trace_id)
      
      results_print << print_ticket_profit(account, trace, range) if range
    end
    
    puts "  Total de registros Método 2: #{total_registros_method2}"
    puts "  Total profit: #{trace_profit.round(2)}, Total fee: #{trace_fee.round(2)}"
    puts "  Total geral: #{(trace_profit + trace_fee).round(2)}"
    puts ""
    
    # Ensure consistent rounding to 2 decimal places
    account_total_method1 = (account_traces_profit + account_traces_fee).round(2)
    trace_total_method2 = (trace_profit + trace_fee).round(2)
    
    # Método 3: Usando ProfitCalculationService para cálculos consistentes
    puts "=== MÉTODO 3: Usando ProfitCalculationService ==="
    
    consistent_profit = ProfitCalculationService.calculate_consistent_profit(account_id)
    puts "  Total profit (direto do banco): #{consistent_profit.round(2)}"
    
    order_based_profit = ProfitCalculationService.calculate_order_based_profit(account_id)
    puts "  Total profit (via orders, distinto): #{order_based_profit.round(2)}"
    
    reconciled_profit = ProfitCalculationService.calculate_reconciled_profit(account_id)
    puts "  Total profit (apenas conciliadas): #{reconciled_profit.round(2)}"
    
    # Cálculo de Fee (mantido aqui pois não faz parte do ProfitCalculationService)
    attributes = { account: account }
    attributes[:closed_at] = range if range
    account_records = account.public_send(model).where(**attributes)
    account_fee = account_records.sum(:fee).to_f
    puts "  Total fee (calculado aqui): #{account_fee.round(2)}"
    
    # Total geral usando o profit consistente + fee
    consistent_total = (consistent_profit + account_fee).round(2)
    puts "  Total geral (profit consistente + fee): #{consistent_total}"
    puts ""
    
    # Comparando os métodos
    puts "=== COMPARAÇÃO ENTRE MÉTODOS ==="
    puts "Método 1 (account.traces) - registros: #{total_registros_method1}, total: #{account_total_method1}"
    puts "Método 2 (traces.uniq) - registros: #{total_registros_method2}, total: #{trace_total_method2}"
    puts "Método 3 (ProfitCalculationService) - total consistente: #{consistent_total}"
    puts "  Total recomendado para uso (consistente): #{consistent_total}"
    puts ""

    # Lógica de divergência (comparando Método 1 com Método 3 consistente)
    divergence = (account_total_method1 - consistent_total).abs
    has_divergence = divergence > 0.01 # Define uma tolerância pequena
    missing_count = (total_registros_method1 - account_records.count).abs

    check_null_orders(account_id, month_year)

    # Retornar um hash com os resultados e a indicação de divergência
    {
      account_total_method1: account_total_method1,
      trace_total_method2: trace_total_method2,
      consistent_total: consistent_total,
      has_divergence: has_divergence,
      divergence: divergence,
      missing_count: missing_count, # Ou outra métrica relevante para a causa
      correct_total: consistent_total # O total consistente é o recomendado
    }
  end

  def self.check_null_orders(account_id = 12, month_year = nil)
    account = Account.find(account_id)
    order_nil_transactions = Transaction.where(account: account).select{ |t| t.orders.empty? }
    account_transactions = account.transactions
    transactions = Transaction.where(account: account)

    puts "=== Transactions Orders Nil: #{order_nil_transactions.count}\n\r"
    puts "=== Account Transactions: #{account_transactions.count}\n\r"
    puts "=== Transactions: #{transactions.count}\n\r"

    diff1 = order_nil_transactions.pluck(:ids) - account_transactions.ids
    diff2 = account_transactions.ids - order_nil_transactions.pluck(:ids)

    puts "=== order_nil_transactions.pluck(:ids) - account_transactions.ids 1: #{diff1}\n\r"
    puts "=== account_transactions.ids - order_nil_transactions.pluck(:ids) 2: #{diff2}\n\r"

  end

  def self.print_ticket_profit(account, trace, range = nil)
    type = account.copy? ? :masters : :slaves

    results = []
    trace.search_date_begin = range&.first
    trace.search_date_end = range&.last
    trace.data_scope(type, :all).each_with_index do |data, index|
      results << "Index: #{index} - Ticket: #{data&.position_id} - Profit: #{data.profit} - Fee: #{data.fee.to_f}"
    end
    results
  end
end
