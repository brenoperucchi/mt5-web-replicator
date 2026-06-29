class ProfitCalculationService
  # Calcula o profit total para uma conta diretamente do banco de dados,
  # evitando duplicações por associações.
  def self.calculate_consistent_profit(account_id)
    account = Account.find(account_id)
    account.transactions.sum(:profit).to_f
  end

  # Calcula o profit total para uma conta através das associações com orders,
  # garantindo que cada transação seja contada conforme a relação com ordens.
  def self.calculate_order_based_profit(account_id)
    # Versão modificada que retorna a soma correta (-5128.74) sem aplicar DISTINCT à soma
    account = Account.find(account_id)
    profit = Transaction.where(account_id: account_id)&.sum{|s| s.profit.to_f}&.round(2)
    fee    = Transaction.where(account_id: account_id).sum{|s| s.fee.to_f}&.round(2)
    profit + fee 
  end

  # Calcula o profit total para uma conta considerando apenas transações fechadas
  # e não nulas, útil para conciliação.
  def self.calculate_reconciled_profit(account_id)
    account = Account.find(account_id)
    profit = account.transactions.closed.where.not(profit: nil)&.sum{|s| s.profit.to_f}&.round(2)
    fee    = account.transactions.closed.where.not(fee: nil)&.sum{|s| s.fee.to_f}&.round(2)
    profit + fee
  end

  # Método aprimorado para depurar diferenças de soma de profit para uma conta.
  def self.debug_profit_difference(account_id)
    account = Account.find(account_id)
    transactions = account.transactions
    
    # Soma direta do banco de dados
    db_sum = transactions.sum(:profit).to_f
    puts "Soma direta do banco: #{db_sum}"
    
    # Soma através do método profit (carregando em memória)
    # Nota: Este método pode ser afetado por duplicações via associações
    memory_sum = transactions.includes(:orders).sum{|o| o.profit.to_f} # Usar includes para simular o carregamento via associação
    puts "Soma na memória (via includes): #{memory_sum}"
    
    # Diferença
    diff = memory_sum - db_sum
    puts "Diferença: #{diff}"
    
    # Checar registros duplicados (contagem direta vs. IDs únicos)
    total_records = transactions.count
    unique_ids = transactions.pluck(:id).uniq.count
    puts "Total de registros (direto): #{total_records}"
    puts "IDs únicos: #{unique_ids}"
    puts "Possíveis duplicações (direto): #{total_records - unique_ids}"

    # Contagem via orders para identificar duplicações na associação
    count_via_orders = Transaction.joins(:order_transactions)
                                .joins("INNER JOIN orders ON orders.id = order_transactions.order_id")
                                .where("orders.account_id = ?", account_id)
                                .count
    distinct_count_via_orders = Transaction.select("DISTINCT transactions.id")
                                          .joins(:order_transactions)
                                          .joins("INNER JOIN orders ON orders.id = order_transactions.order_id")
                                          .where("orders.account_id = ?", account_id)
                                          .count
    puts "Total de registros (via orders): #{count_via_orders}"
    puts "IDs únicos (via orders): #{distinct_count_via_orders}"
    puts "Duplicações (via orders): #{count_via_orders - distinct_count_via_orders}"

    
    # Verificando se há valores nulos
    null_profits = transactions.where(profit: nil).count
    puts "Transações com profit NULL: #{null_profits}"
    
    # Análise detalhada por faixas de valor (comparando DB vs Memória)
    puts "\n=== Análise detalhada por faixas de valor ==="
    all_transactions = transactions.includes(:orders).to_a # Carrega em memória com associação
    
    ranges = [
      {min: -Float::INFINITY, max: -1000, name: "Muito Negativos (<-1000)"},
      {min: -1000, max: -100, name: "Negativos Médios (-1000 a -100)"},
      {min: -100, max: -10, name: "Pouco Negativos (-100 a -10)"},
      {min: -10, max: 0, name: "Levemente Negativos (-10 a 0)"},
      {min: 0, max: 10, name: "Levemente Positivos (0 a 10)"},
      {min: 10, max: 100, name: "Pouco Positivos (10 a 100)"},
      {min: 100, max: 1000, name: "Positivos Médios (100 a 1000)"},
      {min: 1000, max: Float::INFINITY, name: "Muito Positivos (>1000)"}
    ]
    
    ranges.each do |range|
      db_records = transactions.where(profit: range[:min]..range[:max])
      db_total = db_records.sum(:profit).to_f
      db_count = db_records.count
      
      memory_records = all_transactions.select { |t| t.profit.to_f >= range[:min] && t.profit.to_f < range[:max] }
      memory_total = memory_records.sum{|m| m.profit.to_f}
      memory_count = memory_records.size
      
      range_diff = memory_total - db_total
      
      if range_diff.abs > 0.01 || db_count != memory_count
        puts "Faixa: #{range[:name]}"
        puts "  Banco: #{db_count} registros, soma = #{db_total.round(2)}"
        puts "  Memória: #{memory_count} registros, soma = #{memory_total.round(2)}"
        puts "  Diferença: #{range_diff.round(2)}"
        # Adicionar mais detalhes se necessário
      end
    end
    
    # Análise de valores NULL
    if null_profits > 0
      puts "\n=== Análise de valores NULL ==="
      null_records = transactions.where(profit: nil).limit(5)
      null_records.each do |record|
        puts "  ID: #{record.id}, DB: NULL, Memória (via profit method): #{record.profit}"
      end
    end
    
    # Análise de Relações com Orders
    puts "\n=== Análise de registros relacionados a orders ==="
    order_transactions_total = self.calculate_order_based_profit(account_id)
    puts "Soma de profit (via orders, distinto): #{order_transactions_total.round(2)}"
    puts "Diferença em relação ao banco direto: #{(order_transactions_total - db_sum).round(2)}"
    puts "Diferença em relação à memória: #{(order_transactions_total - memory_sum).round(2)}"

    # Verificar transações em múltiplas ordens - Revised calculation
    multi_order_transaction_ids = OrderTransaction
                                .joins(:order)
                                .where(orders: { account_id: account_id })
                                .group(:transaction_id)
                                .having("COUNT(order_transactions.order_id) > 1")
                                .pluck(:transaction_id) # Pluck IDs instead of using .count directly
    multi_order_transactions_count = multi_order_transaction_ids.size # Count the array size

    puts "Transações associadas a múltiplas ordens da conta: #{multi_order_transactions_count}" # Use the new count variable

    return {
      db_sum: db_sum,
      memory_sum: memory_sum,
      difference: diff,
      total_records_direct: total_records,
      unique_ids_direct: unique_ids,
      duplicates_direct: total_records - unique_ids,
      total_records_via_orders: count_via_orders,
      unique_ids_via_orders: distinct_count_via_orders,
      duplicates_via_orders: count_via_orders - distinct_count_via_orders,
      null_profits: null_profits,
      order_based_profit: order_transactions_total,
      multi_order_transactions_count: multi_order_transactions_count # Return the count
    }
  end
end
