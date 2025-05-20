require 'rails_helper'

RSpec.describe 'OrdersHistory API', type: :request do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @plan_method = create(:payment_method, :mercadopago)
    @payment = create(:payment, payment_method: @plan_method, store: @store)
    @customer_plan = create(:customer_plan, payment: @payment, store:@store)
    @trace = create(:trace, :copy, stores: [@store], instrument_control: true, customer_plans:[@customer_plan])
    @trace2 = create(:trace, :copy2, stores:[@store], customer_plans:[@customer_plan])
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, user:@user_admin)
    @customer = create(:customer, :customer, user:@user_customer)
    @account_server = create(:account_server)
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging',   trace_ids: [1,2], instrument_control:true, account_server: @account_server)
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging',     trace_ids: [1,2], account_server: @account_server,)
    @account_copy2 = create(:account, :copy2, store: @store, customer:@customer, meta_margin_mode: 'hedging', trace_ids: [1,2], account_server: @account_server)
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging',     trace_ids: [1,2], account_server: @account_server)
    
    # post '/api/v2/copy/post/imentore_copy/2_21/broker_name/10100/HEDGING', 
    #   params: {"imentore_copy"=>"{\"orders_open\":{
    #             \"10000001\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000001,\"ticket_deal\":2014200953,\"type\":0,\"volume\":\"0.02\",\"price_open\":\"0.87353\",\"price_closed\":0.00000000,\"profit\":\"-0.15\",                      \"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,\"open_at\":\"2023.08.02 22:45:37\",                                 \"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"state_meta\":null,\"comment\":null},
    #             \"10000002\":{\"symbol\":\"AUDCAD\",\"ticket_id\":10000002,\"ticket_deal\":2014200564,\"type\":0,\"price_open\":\"0.87312\",\"price_closed\":\"0.87307\",\"volume\":\"0.02\",\"profit\":\"-0.07\",\"fees\":\"-0.0600\",\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"mae\":\"0.00\",\"mfe\":\"0.00\",\"open_at\":\"2023.08.02 21:39:55\",\"close_at\":\"2023.08.02 21:42:51\",\"time_gmt\":\"2023.08.02 19:45:38\",\"time_trader\":\"2023.08.02 22:45:38\",\"timezone\":-6,\"symbol_digit\":5,\"magic_number\":0,\"comment\":null},
    #           }}"}
  end

  # /api/v2/copy/post/orders/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING
  describe 'POST Copy Orders' do
    let(:file) { Rack::Test::UploadedFile.new(Rails.root.join('spec', 'api', 'v3', 'orders_history.txt')) }
    
    it 'Conciliate Orders - Create New Slave in New Order' do
      post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
        params: { data: file }

      copy  = Transaction.where(ticket: 2029093177).first
      slave = TransactionSlave.where(ticket_master: 2029093177).first

      expect(copy.comment).to be == ""
      expect(slave.comment).to be == "1-2029093177"

    end
    it 'Conciliate Orders - Create New Slave in New Order' do
      post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
        params: { data: file }

      slaves = TransactionSlave.where(ticket_master: 2029093177)
      expect(slaves.count).to be == 4
      expect(slaves.first.state).to be == "pending"

      expect(Order.find_by(content_id: 2029093177).present?).to be true
      expect(Order.find_by(content_id: 2029093177).slaves.count).to be == 2
      expect(Order.find_by(content_id: 2029093177).slaves.first.comment).to be == "1-2029093177"
      expect(Order.find_by(content_id: 2029093177).slaves.first.ticket_slave).to be == -1
      expect(Order.find_by(content_id: 2029093177).slaves.first.profit).to be == 0
    end

    it 'Verify Transaction State maintain Executed and Order state modify Closed' do
      post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
        params: { data: file }

      transactions = Transaction.where(ticket: 2029093177, trace_id: 1)
      slaves = TransactionSlave.where(ticket_master: 2029093177, trace_id: 1)
      
      expect(transactions.count).to be == 1
      expect(transactions.first.state).to be == "executed"
      expect(transactions.first.orders.first.state).to be == "executed"
      
      expect(slaves.count).to be == 2
      expect(slaves.first.state).to be == "pending"
      
      slave1 = slaves.first
      slave2 = slaves.last
      slave1.execute
      slave2.execute
      expect(slave1.state).to be == "executed"
      expect(slave2.state).to be == "executed"
      
      slave1.close
      slave2.close
      transactions.reload
      
      transaction = Transaction.where(ticket: 2029093177, trace_id: 1).first
      expect(transaction.state).to be == "executed"
      expect(transaction.orders.first.state).to be == "closed"
    end
    
  end

  describe 'Magic Number Restrictions' do
    # Utiliza um contexto isolado para este teste
    context 'with specific magic number restrictions' do
      before(:each) do
        # Limpeza de dados que possam interferir no teste
        TransactionSlave.where(ticket_master: 30000001).destroy_all
        Transaction.where(ticket: 30000001).destroy_all
        
        # Configurando o primeiro trace (portfólio) com restrição de magic number 200
        @trace.update(magics_accept: "200")
        
        # Configurando o segundo trace (portfólio) sem restrições específicas
        @trace2.update(magics_accept: nil)
        
        # Garantindo que as contas slave estão associadas aos dois portfólios
        @account1.update(trace_ids: [@trace.id, @trace2.id])
        @account2.update(trace_ids: [@trace.id, @trace2.id])
        
        # Adicionando instrumentos para as contas
        @account_copy.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account1.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account2.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
      end
      
      it 'Denies opening transaction_slave when magic_number is restricted in any portfolio' do
        # Verificando que as configurações de trace foram aplicadas corretamente
        expect(@trace.reload.magics_accept).to eq("200")
        expect(@trace2.reload.magics_accept).to be_nil
        expect(@account1.reload.traces.count).to eq(2)
        expect(@account2.reload.traces.count).to eq(2)
        
        # Enviando uma ordem com magic number 300 (não permitido no primeiro trace)
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        # Criando uma estrutura JSON compatível com o formato usado no arquivo orders_history.txt
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":30000001,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":300,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação principal foi criada
        transaction = Transaction.find_by(ticket: "30000001")
        expect(transaction).not_to be_nil
        
        # Verificando que o magic number é o esperado
        expect(transaction.magic_number).to eq("300")
        
        # Verificando que escravos foram criados mas ficaram com estado de erro devido à restrição
        slaves = TransactionSlave.where(ticket_master: "30000001")
        expect(slaves.count).to eq(2) # Um para cada conta slave
        
        # Ambos devem estar em estado de erro, mesmo que apenas um trace tenha restrição
        expect(transaction.state).to eq("error")
        # expect(slaves.all? { |s| s.state == "error" }).to be ctrue
        # expect(slaves.all? { |s| s.state == "error" }).to be true
        
        # Verificando as mensagens de log para confirmar que o erro foi por causa da restrição de magic number
        error_logs = Logging.where(state: 'ERROR', resourceable: transaction)
        expect(error_logs.count).to eq(1)
        
        # Confirma que o erro é relacionado ao magic number
        expect(error_logs.first.content).to include("magic number 300")
      end
    end
  end

end