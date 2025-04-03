class TestService
  extend ApplicationHelper
  def self.check_slave_conciliated(account_id = 23, store_id = 1, range = false)
    # Account.find(38).update(app_send_orders_history: true)
    account = Account.find(account_id)
    trace_name = "conciliated#{account.name}"

    trace = Trace.includes(:store_traces).where(name: trace_name, name_id: -1, store_traces:{store_id: store_id}).take

    trace_slaves_profit = 0
    trace_slaves_fee = 0
    trace_slaves_count = 0
    profit_total = 0
    results = []
    trace = account.traces.each do |trace|
      if range
        range = DateTime.now.beginning_of_month..DateTime.now.end_of_month
        trace_slaves = trace.slaves.where.not(conciliated_at: nil).where(closed_at: range)
      else
        trace_slaves = trace.slaves
      end
      
      results << "Trace: #{trace.id} Name: #{trace.name} - Slaves Count: #{trace_slaves.count} - Slaves Profit: #{trace_slaves.sum(:profit).round(2)} - Slaves Fee: #{trace_slaves.sum(:fee).round(2)}"
      trace_slaves_profit += trace_slaves.sum(:profit)
      trace_slaves_fee    += trace_slaves.sum(:fee)
      trace_slaves_count  += trace_slaves.count

    end
    puts "\n"
    puts results.join("\n")
    puts "\n"
    puts  "Fees: Total =  #{trace_slaves_fee.round(2)}"
    puts  "Profit Total = #{trace_slaves_profit.round(2)}"
    puts  "Meta Trader Profit = #{(trace_slaves_profit + trace_slaves_fee).round(2)}"
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

  def self.check_transaction_conciliated(account_id = 20, store_id = 1, range = false)
    account    = Account.find(account_id)
    trace_name = "conciliated#{account.name}"
    trace      = Trace.includes(:store_traces).where(name: trace_name, name_id: -1, store_traces:{store_id: store_id}).take
  
    trace_slaves_profit = 0
    trace_slaves_fee    = 0
    trace_slaves_count  = 0
    profit_total        = 0
    results             = []

    trace = account.traces.each do |trace|
      if range
        range = (DateTime.now.beginning_of_month - 1.month)..DateTime.now.end_of_month
        trace_slaves = trace.transactions.where.not(conciliated_at: nil).where(closed_at: range)
      else
        trace_slaves = trace.transactions
      end
      
      results << "Trace: #{trace.id} Name: #{trace.name} - Slaves Count: #{trace_slaves.count} - Slaves Profit: #{trace_slaves.sum(:profit)} - Slaves Fee: #{trace_slaves.sum(:fee)}"
      trace_slaves_profit += trace_slaves.sum(:profit)
      trace_slaves_fee    += trace_slaves.sum(:fee)
      trace_slaves_count  += trace_slaves.count
    end
    
    puts "\n"
    puts results.join("\n")
    puts "\n"
    puts  "Fees: Total =  #{trace_slaves_fee.round(2)}"
    puts  "Profit Total = #{trace_slaves_profit.round(2)}"
    puts  "Meta Trader Profit = #{(trace_slaves_profit + trace_slaves_fee).round(2)}"
  end
end