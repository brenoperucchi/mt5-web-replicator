namespace :maintenance do
  desc "Gerencia transações órfãs (sem associação com orders)"
  task manage_orphaned_transactions: :environment do
    # Criando log para rastreabilidade
    puts "==== Iniciando manutenção de transações órfãs ===="
    puts "Data/hora: #{Time.current}"
    
    # Encontrar todas as transações órfãs
    orphaned_transactions = Transaction.orphaned
    total_orphaned = orphaned_transactions.count
    puts "Total de transações órfãs encontradas: #{total_orphaned}"
    
    if total_orphaned > 0
      # Tentativa de correção automática
      puts "Tentando corrigir automaticamente..."
      result = Transaction.fix_all_orphaned
      puts "#{result[:fixed]} de #{result[:orphaned]} transações foram corrigidas automaticamente"
      
      # Criando relatório detalhado das transações que não puderam ser corrigidas
      still_orphaned = Transaction.orphaned
      if still_orphaned.count > 0
        puts "\nTransações que não puderam ser corrigidas:"
        still_orphaned.find_each do |transaction|
          puts "ID: #{transaction.id}, Trace: #{transaction.trace_id}, Account: #{transaction.account_id}, Created: #{transaction.created_at.to_s(:short)}"
        end
        
        # Se configurado para limpar transações antigas, executamos a limpeza
        if ENV['CLEAN_OLD_ORPHANED'] == 'true'
          days = (ENV['CLEAN_OLDER_THAN_DAYS'] || 30).to_i
          puts "\nRemovendo transações órfãs com mais de #{days} dias..."
          result = Transaction.clean_orphaned(days)
          puts "#{result[:deleted]} transações órfãs antigas foram removidas"
        end
      end
    end
    
    # Verificar se há alertas ativos não resolvidos
    active_alerts = SystemAlert.orphaned_transactions.unresolved.count
    puts "\nExistem #{active_alerts} alertas ativos sobre transações órfãs"
    
    # Resumo para alertar sobre inconsistências nos totais
    puts "\nVerificando inconsistências nos totais de contas..."
    Account.find_each do |account|
      next if account.traces.empty?
      
      # Usando o TestService para verificar se há discrepâncias
      begin
        check_result = TestService.check(account.id, nil, model: :transactions, association: :transactions)
        
        if check_result[:has_divergence]
          divergence = check_result[:divergence].abs
          if divergence > 0.01 # Ignorando diferenças mínimas que podem ser apenas arredondamento
            puts "Conta #{account.id} (#{account.name}): Diferença de #{divergence} detectada"
            
            # Criar alerta para esta discrepância
            SystemAlert.create_calculation_discrepancy_alert(
              account, 
              {
                trace_based_total: check_result[:trace_based_total],
                account_based_total: check_result[:account_based_total],
                difference: check_result[:divergence],
                missing_transactions: check_result[:missing_count]
              }
            )
          end
        end
      rescue => e
        puts "Erro ao verificar conta #{account.id}: #{e.message}"
      end
    end
    
    puts "==== Manutenção de transações órfãs concluída ===="
  end
  
  desc "Limpa transações órfãs antigas"
  task clean_old_orphaned: :environment do
    days = (ENV['DAYS'] || 30).to_i
    puts "Removendo transações órfãs com mais de #{days} dias..."
    result = Transaction.clean_orphaned(days)
    puts "#{result[:deleted]} transações órfãs antigas foram removidas"
  end
  
  desc "Verifica discrepâncias nos cálculos de totais das contas"
  task check_account_discrepancies: :environment do
    puts "Verificando discrepâncias nos totais de contas..."
    discrepancies_found = 0
    
    Account.find_each do |account|
      next if account.traces.empty?
      
      begin
        check_result = TestService.check(account.id, nil, model: :transactions, association: :transactions)
        
        if check_result[:has_divergence]
          divergence = check_result[:divergence].abs
          if divergence > 0.01
            discrepancies_found += 1
            puts "Conta #{account.id} (#{account.name}): Diferença de #{divergence} detectada"
            
            # Detalhes da divergência
            puts "  Trace-based total: #{check_result[:trace_based_total]}"
            puts "  Account-based total: #{check_result[:account_based_total]}"
            puts "  Transações faltando: #{check_result[:missing_count]}"
          end
        end
      rescue => e
        puts "Erro ao verificar conta #{account.id}: #{e.message}"
      end
    end
    
    puts "Total de contas com discrepâncias: #{discrepancies_found}"
  end
end