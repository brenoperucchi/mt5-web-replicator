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

    csv = CSV.parse(csv_content, quote_char: ',') # Parseia o conteúdo do CSV
    csv.each_with_index do |row, index|
      next if index == 0
      comment = row[0].split('(Magic')[0].strip
      magic_number = row[0][/\(Magic: \#(\d+)\)/, 1]
      profit = row[1].gsub(",", ".").to_f

      time_string = row[2]
      parsed_time = DateTime.strptime(time_string + Time.now.zone , "%H:%M %d/%m/%Y %Z")

      # Aplicando a zona horária local
      created_at = parsed_time.new_offset(DateTime.now.zone.to_f / 24)

      type = row[3].downcase == "venda" ? "1" : "0"


      volume = row[4].to_f
      symbol = row[5]
      dates = created_at -1.minute..created_at + 1.minute
      # Order.create("")
      transactions =  Transaction.where(symbol: symbol, magic_number: magic_number, profit: profit, closed_at: dates, lot: volume, ordertype: type).where("comment LIKE ?", "%#{magic_number}%")
      # transactions = Transaction.where(symbol: symbol, magic_number: magic_number, profit: profit, ordertype: type)
      # binding.pry unless transactions.blank?
      
      binding.pry unless transactions.blank?
      next unless transactions.blank?

      account_copy = trace.accounts.copy.first

      transaction = Transaction.create!(symbol: symbol, magic_number: trace.magic_number_restrict?.try(:first), profit: profit, closed_at: dates, lot: volume, ordertype: type, ticket: -1, trace: trace, account: account_copy, comment: "IMPORT FROM MESSAGE", created_at:created_at, closed_at: created_at, message: self)
    

      if transaction.valid?
        transaction.close 
        if Order.create(content_id: -1, symbol: symbol, message: self, messages:[self], trace:trace, account: account_copy, store: trace.store, state: :executed, transactions:[transaction]).valid?
          count_orders += 1 if transaction.try(:valid?)
        else
          transaction.destroy
        end
      end
    end
    puts "Orders created: #{count_orders}"
    puts "Orders CSV: #{csv.count}"
    return
  end

end