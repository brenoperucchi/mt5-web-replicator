class TestService
  extend ApplicationHelper

  def self.check_slave(account_id = 23, month_year = nil)
    account = Account.find(account_id)
    self.check(account_id, month_year, model: :slaves, association: :slaves)
  end

  def self.check_copy(account_id = 23, month_year = nil)
    account = Account.find(account_id)
    
    # Antes de verificar as estatísticas, vamos tentar corrigir as transações órfãs
    # Essa chamada só acontecerá em ambiente de produção ou desenvolvimento, não em testes
    # unless Rails.env.test?
    #   # Procura por transações órfãs para esta conta
    #   orphaned_transactions = Transaction.orphaned.where(account_id: account_id)
      
    #   if orphaned_transactions.any?
    #     puts "\nEncontramos #{orphaned_transactions.count} transações órfãs para a conta #{account_id}"
    #     fixed_count = 0
        
    #     # Tenta corrigir cada transação órfã
    #     orphaned_transactions.each do |transaction|
    #       fixed = transaction.ensure_order_association
    #       fixed_count += 1 if fixed
    #     end
        
    #     puts "Corrigidas automaticamente: #{fixed_count} transações\n\n"
    #   end
    # end
    
    check_result = self.check(account_id, month_year, model: :transactions, association: :transactions)
    
    # Se houver uma divergência, avise o usuário de forma clara
    if check_result[:has_divergence]
      puts "\n============ AVISO IMPORTANTE ============"
      puts "Foi encontrada uma divergência de #{check_result[:divergence].abs} entre os cálculos"
      puts "Causa: #{check_result[:missing_count]} transações não estão sendo consideradas no cálculo direto"
      puts "Estas transações pertencem ao trace: #{check_result[:trace_id]} (#{check_result[:trace_name]})"
      puts "O problema ocorre porque estas transações não têm a associação 'orders' preenchida corretamente"
      puts "O valor correto total é: #{check_result[:correct_total]}"
      puts "=========================================="
    end
    
    # Sempre retorne o valor correto (baseado no método trace)
    check_result[:correct_total]
  end

  # Método para corrigir as transações sem associação "orders" - pode ser executado para resolver o problema
  def self.fix_orphaned_transactions(account_id)
    account = Account.find(account_id)
    orphaned_count = 0
    fixed_count = 0
    
    # Encontra todas as transações através dos traces, independente da relação orders
    account.traces.each do |trace|
      trace_transactions = trace.transactions.where(account: account)
      
      trace_transactions.each do |transaction|
        # Verifica se a transação não tem orders relacionadas
        if transaction.orders.empty?
          orphaned_count += 1
          puts "Transação órfã encontrada: ID #{transaction.id}, Trace #{trace.id}, Profit #{transaction.profit}"
          
          # Verifica se existe alguma order que possa ser relacionada
          # Poderia ser adaptado conforme a lógica específica do seu sistema
          order = Order.where(trace: trace, account: account).first
          
          if order
            # Cria a associação entre a transação e a order
            OrderTransaction.create(order_id: order.id, transaction_id: transaction.id)
            fixed_count += 1
            puts "  - Associação criada com Order ID: #{order.id}"
          else
            puts "  - Não foi encontrada uma Order adequada para associação"
          end
        end
      end
    end
    
    puts "Total de transações órfãs encontradas: #{orphaned_count}"
    puts "Total de transações corrigidas: #{fixed_count}"
    
    # Retorna um resumo das ações realizadas
    {
      account_id: account_id,
      orphaned_transactions: orphaned_count,
      fixed_transactions: fixed_count
    }
  end

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

  def methods
    Account.find(38).update(api_send_orders_history: true)
    TransactionSlave.where.not(conciliated_at:nil).sum(:profit)
    TransactionSlave.where.not(conciliated_at:nil).update_all(conciliated_at:nil)
    Message::V3::MetaSlave.find(7150908).execute_again_conciliated
  end

  def self.reset(account_id = 23)
    # Message::V3::MetaSlave.find(7151133).reset
    # Message::V3::MetaSlave.last.reset
    account = Account.find(account_id)
    trace_name = "conciliated##{account.name}"
    Trace.find_by(name: trace_name)&.destroy
    puts Order.where(account: account).conciliated.destroy_all
    puts TransactionSlave.where(account: account).conciliated.update_all(conciliated_at:nil)
    puts Transaction.where(account: account).conciliated.update_all(conciliated_at:nil)

    # Account.find(account_id).update(api_send_orders_history: true)
    # Message::V3::MetaSlave.find(7151133).execute_conciliated
    # Message::V3::MetaSlave.last.execute_conciliated
  end
  
  def self.restart(kind = 'COPY', account_id = 23)
    # self.reset(account_id)
    # Message::V3::MetaSlave.find(7151133).reset
    # # Message::V3::MetaSlave.last.reset
    # puts TransactionSlave.conciliated.update_all(conciliated_at:nil)
    # puts Transaction.conciliated.update_all(conciliated_at:nil)
    # puts Order.conciliated.destroy_all

    Transaction.last.destroy
    account = Account.find(account_id)
    account.update(api_send_orders_history: true)
    message = Message::V3::MetaCopy.joins(:loggings).where(account: account, loggings: {state: "#{kind}/CONCILIATE"}).last
    message.update(state: 'pending')
    message.execute
    # message.conciliate
    # Message::V3::MetaSlave.find(7151133).execute_conciliated
    # Message::V3::MetaSlave.last.execute_conciliated
  end
  
  def self.soft_reset_transaction(account_id = 20)
    # Message::V3::MetaSlave.find(7151133).reset
    # Message::V3::MetaSlave.last.reset
    account = Account.find(account_id)
    account.update(api_send_orders_history: true)
    # Transaction.where(account: account).conciliated.where.not(conciliated_at:nil).update_all(conciliated_at:nil)
    Order.where(account: account).conciliated.where.not(conciliated_at:nil).update_all(conciliated_at:nil)
  end

  def self.message_check(account_id = 23)
    account = Account.find(account_id)
    account.update(api_send_orders_history: true)
    message = Message::V3::MetaSlave.joins(:loggings).where(account: account, loggings: {state: "SLAVE/CONCILIATE"}).last
    message.reset
    message.execute_conciliated
    puts message.inspect
    puts message.loggings.where(state: "SLAVE/CONCILIATE").count
    puts message.loggings.where(state: "SLAVE/CONCILIATE").last.created_at
    puts message.loggings.where(state: "SLAVE/CONCILIATE").last.updated_at
    
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

  def self.fetch_data(account_id)
    account = Account.find_by(id: account_id)
    return { error: "Account not found" } unless account
  
    # Busca as transações diretamente (já sabemos que os IDs são os mesmos)
    # Seleciona apenas os campos necessários
    transactions = account.transactions.select(:id, :profit, :fee, :created_at, :trace_id).order(:id)
  
    # Calcula os totais diretos a partir dos dados buscados
    total_profit = transactions.sum { |t| t.profit || 0 } # Usar 0 se for nil
    total_fee = transactions.sum { |t| t.fee || 0 }       # Usar 0 se for nil
    total_general = total_profit + total_fee
  
    # Prepara os dados para retorno (opcionalmente limitar a lista se for muito grande)
    transaction_details = transactions.map do |t|
      {
        id: t.id,
        trace_id: t.trace_id, # Para referência
        profit: t.profit,
        fee: t.fee,
        created_at: t.created_at
      }
    end
  
    {
      account_id: account.id,
      transaction_count: transactions.size,
      direct_sum_profit: total_profit.round(2).to_f,
      direct_sum_fee: total_fee.round(2).to_f,
      direct_sum_general: total_general.round(2).to_f,
      # Retorna detalhes de todas as transações. Cuidado se for um número muito grande.
      # Pode-se adicionar .limit(100) na query acima ou pegar uma amostra aqui.
      transaction_details: transaction_details
    }
  end

  def self.compare_ids(account_id)
    account = Account.find(account_id)
    
    # Coletar IDs via query direta (sem distinct)
    direct_ids = account.transactions.pluck(:id)
    
    # Coletar IDs via associação transactions -> distinct
    distinct_ids = account.transactions.distinct.pluck(:id)
    
    # Coletar profits via pluck diretamente do DB - retorna apenas distintos devido à associação
    profits_pluck = account.transactions.pluck(:profit)
    
    # Coletar profits via map (carrega objetos) - ignora o distinct na memória
    profits_map = account.transactions.map(&:profit)
    
    # Coletar profits via select distinct explícito - para demonstrar a consulta correta
    profits_distinct = account.transactions.select("DISTINCT ON (transactions.id) transactions.id, transactions.profit").pluck(:profit)
    
    # Contagens
    direct_count = direct_ids.count
    distinct_count = distinct_ids.count
    pluck_count = profits_pluck.count
    map_count = profits_map.count
    distinct_profits_count = profits_distinct.count
    
    # Somas
    pluck_sum = profits_pluck.compact.sum.to_f
    map_sum = profits_map.compact.sum.to_f
    distinct_sum = profits_distinct.compact.sum.to_f
    
    # Análise de duplicações
    duplicates = direct_ids.size - distinct_ids.size
    duplicate_ids = direct_ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    
    # Resultado para depuração
    {
      account_id: account_id,
      direct_count: direct_count,
      distinct_count: distinct_count,
      pluck_count: pluck_count,
      map_count: map_count, 
      distinct_profits_count: distinct_profits_count,
      duplicates: duplicates,
      duplicate_count: duplicate_ids.size,
      pluck_sum: pluck_sum.round(2),
      map_sum: map_sum.round(2),
      distinct_sum: distinct_sum.round(2),
      
      # Comentar estas linhas se o resultado for muito grande
      # duplicate_ids: duplicate_ids
    }
  end
  
  def self.explain_profit_calculation(account_id)
    account = Account.find(account_id)
    
    # Cálculos com diferentes abordagens
    db_sum = account.transactions.sum(:profit).to_f
    map_sum = account.transactions.map(&:profit).compact.sum.to_f
    distinct_sum = account.transactions.select("DISTINCT ON (transactions.id) transactions.id, transactions.profit").sum(:profit).to_f
    order_based_sum = ProfitCalculationService.calculate_order_based_profit(account_id)
    
    # Estatísticas sobre registros duplicados
    all_ids = account.transactions.joins(:order_transactions).pluck(:id)
    unique_ids = all_ids.uniq
    duplication_factor = all_ids.size.to_f / unique_ids.size
    
    # Análise de transações por Order
    transactions_per_order = Transaction
      .joins(:order_transactions)
      .where(account_id: account_id)
      .group('transactions.id')
      .select('transactions.id', Arel.sql('COUNT(DISTINCT order_transactions.order_id) AS order_count')) # Separate select arguments, use Arel.sql only for aggregate
      .order(Arel.sql('order_count DESC')) # Keep Arel.sql for ORDER BY
      .limit(10)
    
    multi_counted_analysis = transactions_per_order.map do |t|
      {
        transaction_id: t.id,
        order_count: t.order_count, # Podemos usar o nome do atributo diretamente
        profit: Transaction.find(t.id).profit
      }
    end
    
    # Resultados e recomendação
    {
      account_id: account_id,
      db_sum: db_sum.round(2),
      map_sum: map_sum.round(2),
      distinct_sum: distinct_sum.round(2),
      order_based_sum: order_based_sum.round(2),
      duplication_factor: duplication_factor.round(2),
      multi_counted_transactions: transactions_per_order.count,
      multi_counted_examples: multi_counted_analysis,
      recommendation: "Use ProfitCalculationService.calculate_consistent_profit(#{account_id}) para garantir que cada transação seja contada apenas uma vez."
    }
  end
end

# Como usar no console (irb):
# result = TransactionIdComparator.compare_ids(12)
# puts result.to_json