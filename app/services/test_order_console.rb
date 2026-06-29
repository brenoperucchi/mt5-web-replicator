require 'json'
require 'net/http'
require 'uri'
require 'tempfile'

class TestOrderConsole
  def self.run
    # Lê o conteúdo do arquivo orders.json
    orders_file_path = File.join(File.dirname(__FILE__), 'orders.json')
    orders_data = JSON.parse(File.read(orders_file_path))

    # Cria um arquivo temporário com os dados do JSON
    Tempfile.create(['orders', '.json']) do |tempfile|
      tempfile.write(orders_data.to_json)
      tempfile.rewind
      # Modifica os dados do JSON antes de escrever no arquivo temporário
      content_id = orders_data["PositionOrders"][0]["ticketMaster"]
      order = Order.find_by(content_id: content_id)
      if order.present?
        orders_data["PositionOrders"][0]["ticketMaster"] = order.content_id + 1
      end
      orders_data["PositionOrders"][0]["openAt"] = (Time.zone.now + 3.hours).strftime("%Y.%m.%d %H:%M:%S")
      orders_data["PositionOrders"][0]["openAt"] = (Time.zone.now + 3.hours).strftime("%Y.%m.%d %H:%M:%S")
      orders_data["PositionOrders"][0]["timeGMT"] = (Time.zone.now + 3.hours).strftime("%Y.%m.%d %H:%M:%S")
      orders_data["PositionOrders"][0]["timeTrader"] = (Time.zone.now + 3.hours).strftime("%Y.%m.%d %H:%M:%S")
      
      # Reescreve o arquivo temporário com os dados atualizados
      tempfile.truncate(0)
      tempfile.write(orders_data.to_json)
      tempfile.rewind

      # Configura a URL da API
      url = URI.parse("http://localhost:8080/api/v3/copy/post/orders/imentore_copy/3_00_05/xpmt5demo/92033102/HEDGING")

      # Configura o envio do arquivo
      request = Net::HTTP::Post.new(url)
      form_data = [['data', File.open(tempfile.path)]]
      request.set_form(form_data, 'multipart/form-data')

      # Envia a requisição
      response = Net::HTTP.start(url.hostname, url.port, use_ssl: url.scheme == 'https') do |http|
        http.request(request)
      end

      # Exibe a resposta
      puts "Response Code: #{response.code}"
      puts "Response Body: #{response.body}"
    end
  end
end

# Executa o teste
# TestOrderConsole.run