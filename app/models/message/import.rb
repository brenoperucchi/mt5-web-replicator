require 'csv'

class Message::Import < Message::Message
  self.table_name = "messages"
  self.inheritance_column = :_type_disabled


  state_machine :initial => :pending do
  end

  #   def all_loggings
  #   loggings.or(Logging.where(id:logging_orders))
  # end

  def close_orders
  end

  def create_orders(trace)
    csv_content = content.gsub!(/["\\]/, '')
    count_orders = 0
    csv = CSV.parse(csv_content, quote_char: ',') # Parse CSV content

    csv.each_with_index do |row, index|
      next if index == 0 # Skip header row

      order_data = extract_order_data(row)
      next unless order_data

      transaction = create_transaction(order_data, trace)
      next unless transaction&.valid?

      order = create_order(transaction, trace)
      if order&.save
        transaction.close
        count_orders += 1
        self.orders << order
        self.traces = [trace]
      else
        transaction.destroy
      end
    end

    puts "Orders created: #{count_orders}"
    puts "Orders CSV: #{csv.count}"
    return
  end

  def extract_order_data(row)
    comment = row[0]
    magic_number = row[0][/\(Magic: \#(\d+)\)/, 1]
    profit = row[1].gsub(",", ".").to_f
    parsed_time = parse_time(row[2])
    created_at = adjust_time_zone(parsed_time)
    type = row[3].downcase == "venda" ? "1" : "0"
    volume = row[4].to_f
    symbol = row[5]

    return {
            comment: comment, magic_number: magic_number, profit: profit,
            created_at: created_at, type: type, volume: volume, symbol: symbol
           }
  end

  def parse_time(time_string)
    DateTime.strptime(time_string + Time.now.zone , "%H:%M %d/%m/%Y %Z")
  end

  def adjust_time_zone(parsed_time)
    parsed_time.new_offset(DateTime.now.zone.to_f / 24)
  end

  def create_transaction(order_data, trace)
    dates = order_data[:created_at] - 1.minute..order_data[:created_at] + 1.minute
    transactions = Transaction.where(symbol: order_data[:symbol], profit: order_data[:profit], lot: order_data[:volume], ordertype: order_data[:type]).where("comment LIKE ?", "%#{order_data[:magic_number]}%").where.not(state: :pending)
    return if transactions.exists?

    account_copy = trace.accounts.copy.first

    Transaction.create!(
      symbol: order_data[:symbol],
      magic_number: trace.magic_number_restrict?.try(:first),
      profit: order_data[:profit],
      closed_at: dates,
      lot: order_data[:volume],
      ordertype: order_data[:type],
      ticket: -1,
      trace: trace,
      account: account_copy,
      comment: order_data[:comment],
      created_at: order_data[:created_at],
      closed_at: order_data[:created_at],
      message: self
    )
  end

  def create_order(transaction, trace)
    account_copy = trace.accounts.copy.first
    Order.new(
      content_id: -1,
      symbol: transaction.symbol,
      message: self,
      messages: [self],
      trace: trace,
      account: account_copy,
      store: trace.store,
      state: :executed,
      transactions: [transaction]
    )
  end


  # def create_orders(trace)
  #   csv_content = content.gsub!(/["\\]/, '')
  #   count_orders = 0

  #   csv = CSV.parse(csv_content, quote_char: ',') # Parseia o conteúdo do CSV
  #   csv.each_with_index do |row, index|
  #     next if index == 0
  #     comment = row[0]#.split('(Magic')[0].strip
  #     magic_number = row[0][/\(Magic: \#(\d+)\)/, 1]
  #     profit = row[1].gsub(",", ".").to_f

  #     time_string = row[2]
  #     parsed_time = DateTime.strptime(time_string + Time.now.zone , "%H:%M %d/%m/%Y %Z")

  #     # Aplicando a zona horária local
  #     created_at = parsed_time.new_offset(DateTime.now.zone.to_f / 24)

  #     type = row[3].downcase == "venda" ? "1" : "0"


  #     volume = row[4].to_f
  #     symbol = row[5]
  #     dates = created_at -1.minute..created_at + 1.minute
  #     # Order.create("")
  #     transactions =  Transaction.where(symbol: symbol, profit: profit, lot: volume, ordertype: type).where("comment LIKE ?", "%#{magic_number}%")
  #     # transactions = Transaction.where(symbol: symbol, magic_number: magic_number, profit: profit, ordertype: type)

  #     next unless transactions.blank?

  #     account_copy = trace.accounts.copy.first

  #     transaction = Transaction.create!(symbol: symbol, magic_number: trace.magic_number_restrict?.try(:first), profit: profit, closed_at: dates, lot: volume, ordertype: type, ticket: -1, trace: trace, account: account_copy, comment: comment, created_at:created_at, closed_at: created_at, message: self)
    

  #     if transaction.valid?
  #       transaction.close 
  #       order = Order.new(content_id: -1, symbol: symbol, message: self, messages:[self], trace:trace, account: account_copy, store: trace.store, state: :executed, transactions:[transaction])
  #       if order.save
  #         count_orders += 1 if transaction.try(:valid?)
  #         self.orders << order
  #         self.traces << trace
  #       else
  #         transaction.destroy
  #       end
  #     end
  #   end
  #   puts "Orders created: #{count_orders}"
  #   puts "Orders CSV: #{csv.count}"
  #   return
  # end

end