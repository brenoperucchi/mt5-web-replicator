class TestService
  extend ApplicationHelper
  def self.check_slave(account_id = 23, month_year = nil)
    account = Account.find(account_id)
    store_id = 1
    trace_name = "conciliated#{account.name}"

    trace = Trace.includes(:store_traces).where(name: trace_name, name_id: -1, store_traces: { store_id: store_id }).take

    trace_slaves_profit = 0
    trace_slaves_fee = 0
    trace_slaves_count = 0
    results = []
    results_print = []

    # Define range based on month_year parameter
    range = if month_year
              begin
                # Use Time.zone.parse for better timezone handling within Rails
                start_date = Time.zone.parse("#{month_year}-01")
                # Use an exclusive range ending at the beginning of the next month
                # This ensures all moments within the specified month are included.
                start_date.beginning_of_month...start_date.next_month.beginning_of_month
              rescue ArgumentError, TypeError # Catch potential errors from parse
                raise "Invalid month_year format. Use 'YYYY-MM'."
              end
            else
              nil
            end
    traces = account.transaction_slaves.where(account_id:134).map(&:trace_id)
    traces += account.traces&.pluck(:id) if traces.empty?
    trace_slave_ids = []
    trace_slave_trace_ids = []
    traces.uniq.each do |trace_id|
      trace = Trace.find_by(id: trace_id)
      next if trace.nil?
      trace_slaves = range ? trace.slaves.where(closed_at: range, account: account) : trace.slaves.where(account: account)
      # trace_slaves = range ? TransactionSlave.where(trace: trace, closed_at: range, account: account) : TransactionSlave.where(trace: trace, account: account)

      results << "Trace: #{trace.id} Name: #{trace.name} - Slaves Count: #{trace_slaves.count} - Slaves Profit: #{trace_slaves.sum(&:profit).round(2)} - Slaves Fee: #{trace_slaves.sum{|s| s.fee.to_f}.round(2)}"
      trace_slaves_profit += trace_slaves.sum(&:profit)
      trace_slaves_fee += trace_slaves.sum{|s| s.fee.to_f}
      trace_slaves_count += trace_slaves.count
      trace_slave_ids += trace_slaves.ids
      trace_slave_trace_ids += trace_slaves.pluck(:trace_id)

      results_print << print_ticket_profit(account, trace, range) if range
      # puts "Slave ids: #{trace_slaves.pluck(:account_id).uniq.join(", ")}"
    end

    puts "\n"
    puts results.join("\n")
    puts "\n"
    puts "Range: #{I18n.l(range.first, format: :short)} - #{I18n.l(range.last, format: :short)}" if range
    puts "Fees: Total =  #{trace_slaves_fee.round(2)}"
    puts "Profit Total = #{trace_slaves_profit.round(2)}"
    puts "Meta Trader Profit = #{(trace_slaves_profit + trace_slaves_fee).round(2)}"

    # Build attributes hash conditionally
    attributes = { account: account }
    attributes[:closed_at] = range if range

    # Query slaves using the attributes hash
    account_slaves = account.slaves.where(**attributes)
    account_slave_ids = account_slaves.ids
    account_slave_trace_ids = account_slaves.pluck(:trace_id).uniq.compact
    # puts "Trace Slaves Ids: #{trace_slave_ids.uniq.join(", ")}"
    # puts "Account Slaves Ids: #{account_slave_ids.uniq.join(", ")}" # Fixed the method call here
    puts "Diff 1 Slaves Ids: #{(account_slave_ids - trace_slave_ids).uniq.join(", ")}"
    puts "Diff 2 Slaves Ids: #{(trace_slave_ids - account_slave_ids).uniq.join(", ")}"

    puts "Trace Slaves Trace_ids => #{trace_slave_trace_ids&.sort.uniq.join(", ")}"
    puts "Account Slaves Trace_ids => #{account_slave_trace_ids&.sort.uniq.join(", ")}"

    # Calculate profit and fee from the query result
    account_profit = account_slaves.sum(&:profit).round(2)
    account_fee = account_slaves.sum { |s| s.fee.to_f }.round(2)

    puts "Account Profit => #{account_profit}"
    puts "Account Fee => #{account_fee}"
    puts "Account Total => #{account_profit + account_fee}"
    # puts results_print.join("\n") if range
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

  def self.check_copy(account_id = 20, month_year = nil)
    store_id  = 1
    # account_id = 20
    # account_id = 23
    # account_id = 134
    # account_id = 38
    # account_id = 23
    # store_id   = 1
    # store_id   = 2
    # store_id   = 3
    # store_id   = 4

    # account_id = 20
    # month_year = '2023-10'
    account    = Account.find(account_id)
    trace_name = "conciliated#{account.name}"
    trace      = Trace.includes(:store_traces).where(name: trace_name, name_id: -1, store_traces:{store_id: store_id}).take
  
    trace_slaves_profit = 0
    trace_slaves_fee    = 0
    trace_slaves_count  = 0
    profit_total        = 0
    results             = []
    results_print       = []

    # Define range based on month_year parameter
    range = if month_year
              begin
                # Use Time.zone.parse for better timezone handling within Rails
                start_date = Time.zone.parse("#{month_year}-01")
                # Use an exclusive range ending at the beginning of the next month
                # This ensures all moments within the specified month are included.
                start_date.beginning_of_month...start_date.next_month.beginning_of_month
              rescue ArgumentError, TypeError # Catch potential errors from parse
                raise "Invalid month_year format. Use 'YYYY-MM'."
              end
            else
              nil
            end

    traces = account.transaction_slaves.where(account_id:134).map(&:trace_id)
    traces += account.traces&.pluck(:id) if traces.empty?
    trace_slave_ids = []
    trace_slave_trace_ids = []
    traces.uniq.each do |trace_id|
      trace = Trace.find_by(id: trace_id)
      trace_slaves = range ? trace.transactions.where(closed_at: range, account: account) : trace.transactions.where(account: account)
      
      results << "Trace: #{trace.id} Name: #{trace.name} - Slaves Count: #{trace_slaves.count} - Slaves Profit: #{trace_slaves.sum(:profit)} - Slaves Fee: #{trace_slaves.sum(:fee)}"
      trace_slaves_profit += trace_slaves.sum(:profit)
      trace_slaves_fee    += trace_slaves.sum(:fee)
      trace_slaves_count  += trace_slaves.count
      # results_print << print_ticket_profit(account, trace, range)
    end
    
    puts "\n"
    puts results.join("\n")
    puts "\n"
    puts "Range: #{I18n.l(range.first, format: :short)} - #{I18n.l(range.last, format: :short)}" if range
    puts "Fees: Total =  #{trace_slaves_fee.round(2)}"
    puts "Profit Total = #{trace_slaves_profit.round(2)}"
    puts "Meta Trader Profit = #{(trace_slaves_profit + trace_slaves_fee).round(2)}"
    puts results_print.join("\n")
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