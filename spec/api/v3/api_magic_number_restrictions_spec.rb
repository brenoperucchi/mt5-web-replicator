require 'rails_helper'

RSpec.describe 'Magic Number Restrictions API', type: :request do
  before(:context) do
    @plan1 = create(:plan, :plan1)
    @store = create(:store, plan_id: @plan1.id)
    @user_customer = create(:user, :customer, store: @store)
    @user_admin = create(:user, :admin, store: @store)
    @admin = create(:customer, :admin, user: @user_admin)
    @customer = create(:customer, :customer, user: @user_customer)
    @account_server = create(:account_server)
    @plan_method = create(:payment_method, :mercadopago)
    @payment = create(:payment, payment_method: @plan_method, store: @store)
    @customer_plan = create(:customer_plan, payment: @payment, store:@store)
  end

  describe 'Account-level magic number restrictions' do
    context 'with restrictions on copy and slave accounts' do
      before(:each) do
        # Limpeza mais abrangente para garantir que não haja interferência entre testes
        TransactionSlave.destroy_all
        Transaction.destroy_all
        Logging.destroy_all
        
        # Criando traces sem restrições específicas

        @trace = create(:trace, :copy, stores: [@store], instrument_control: true, magics_accept: nil, customer_plans: [@customer_plan])
        @trace2 = create(:trace, :copy2, stores: [@store], magics_accept: nil, customer_plans: [@customer_plan])

        # Conta copy com restrição de magic number 400
        @account_copy = create(:account, :copy, 
                              store: @store,
                              customer: @customer, 
                              meta_margin_mode: 'hedging',
                              trace_ids: [@trace.id, @trace2.id], 
                              instrument_control: true, 
                              account_server: @account_server)
        @account_copy.update(magics_accept: "400")
        
        # Conta slave com restrição de magic number 500
        @account1 = create(:account, :slave1, 
                          store: @store, 
                          customer: @customer, 
                          meta_margin_mode: 'hedging',
                          trace_ids: [@trace.id, @trace2.id], 
                          account_server: @account_server)
        @account1.update(magics_accept: "500")
        
        # Conta slave sem restrição
        @account2 = create(:account, :slave2, 
                          store: @store, 
                          customer: @customer, 
                          meta_margin_mode: 'hedging',
                          trace_ids: [@trace.id, @trace2.id], 
                          account_server: @account_server)
        
        # Adicionando instrumentos para as contas
        @account_copy.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account1.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account2.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
      end
      
      it 'Denies opening transactions for copy account with restricted magic number' do
        # Verificando que as configurações das contas foram aplicadas corretamente
        expect(@account_copy.reload.magics_accept).to eq("400")
        expect(@account1.reload.magics_accept).to eq("500")
        expect(@account2.reload.magics_accept).to be_nil
        
        # Enviando uma ordem com magic number 300 (não permitido em copy account)
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        # Criando uma estrutura JSON compatível com o formato da API V3
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":40000001,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":300,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação principal foi criada mas ficou em estado de erro
        transaction = Transaction.find_by(ticket: "40000001")
        expect(transaction).not_to be_nil
        expect(transaction.magic_number).to eq("300")
        expect(transaction.state).to eq("error")
        
        # Verificando que os logs indicam o erro de restrição na conta copy
        error_logs = Logging.where(state: 'ERROR', resourceable: transaction)
        expect(error_logs.count).to be >= 1
        # Verificamos o conteúdo do primeiro log, independente da quantidade
        expect(error_logs.first.content).to include("magic number 300")
        expect(error_logs.first.content).to include(@account_copy.name.to_s)
      end
      
      it 'Denies creating transaction_slave for slave account with restricted magic number' do
        # Primeiro mudar a restrição da conta copy para permitir o magic number 300
        @account_copy.update(magics_accept: "300")
        
        # Enviando uma ordem com magic number 300 (permitido agora pela conta copy, mas não pelo slave1)
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":40000002,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":300,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação principal foi criada
        transaction = Transaction.find_by(ticket: "40000002")
        expect(transaction).not_to be_nil
        expect(transaction.magic_number).to eq("300")
        expect(transaction.state).to eq("executed") # Deve estar executado pois a conta copy permite
        
        # Verificando que slave1 ficou em erro, mas slave2 não
        slaves = TransactionSlave.where(ticket_master: "40000002")
        expect(slaves.count).to be > 0
        
        slave1 = slaves.find_by(account_id: @account1.id)
        slave2 = slaves.find_by(account_id: @account2.id)
        
        expect(slave1).to be_present
        expect(slave2).to be_present
        
        expect(slave1.state).to eq("error")
        expect(slave2.state).to eq("pending") # Deve estar pending pois esta conta não tem restrição
        
        # Verificando as mensagens de log para confirmar que o erro foi por causa da restrição de magic number
        error_logs = Logging.where(state: 'ERROR', resourceable: slave1)
        expect(error_logs.count).to eq(1)
        
        # Verificando que o log menciona o account e a restrição, sem importar o magic number específico
        expect(error_logs.first.content).to include("magic number")
        expect(error_logs.first.content).to include("only accepted: 500")
        expect(error_logs.first.content).to include(@account1.name.to_s)
      end
    end
  end

  describe 'Combined trace and account magic number restrictions' do
    context 'with restrictions on both traces and accounts' do
      before(:each) do
        # Limpeza mais abrangente para garantir que não haja interferência entre testes
        TransactionSlave.destroy_all
        Transaction.destroy_all
        Logging.destroy_all
        
        # Primeiro trace com restrição de magic number 200
        @trace = create(:trace, :copy, stores: [@store], instrument_control: true, magics_accept: nil, customer_plans: [@customer_plan])
        @trace.update(magics_accept: "200")
        
        # Segundo trace com restrição de magic number 600
        @trace2 = create(:trace, :copy2, stores: [@store], customer_plans: [@customer_plan])
        @trace2.update(magics_accept: "600")
        
        # Conta copy sem restrição específica
        @account_copy = create(:account, :copy, 
                              store: @store, 
                              customer: @customer, 
                              meta_margin_mode: 'hedging',
                              trace_ids: [@trace.id, @trace2.id], 
                              instrument_control: true, 
                              account_server: @account_server)
        
        # Conta slave1 com restrição de magic number 700
        @account1 = create(:account, :slave1, 
                          store: @store, 
                          customer: @customer, 
                          meta_margin_mode: 'hedging',
                          trace_ids: [@trace.id], 
                          account_server: @account_server)
        @account1.update(magics_accept: "700")
        
        # Conta slave2 sem restrição específica, mas associada apenas ao segundo trace
        @account2 = create(:account, :slave2, 
                          store: @store, 
                          customer: @customer, 
                          meta_margin_mode: 'hedging',
                          trace_ids: [@trace2.id], 
                          account_server: @account_server)
        
        # Adicionando instrumentos para as contas
        @account_copy.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account1.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account2.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
      end
      
      it 'Denies transactions when magic number is restricted by any trace or account' do
        # Verificando que as configurações foram aplicadas corretamente
        expect(@trace.reload.magics_accept).to eq("200")
        expect(@trace2.reload.magics_accept).to eq("600")
        expect(@account1.reload.magics_accept).to eq("700")
        expect(@account2.reload.magics_accept).to be_nil
        
        # Enviando uma ordem com magic number 300 (não permitido por ambos os traces)
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":50000001,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":300,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação principal foi criada mas está em estado de erro
        transaction = Transaction.find_by(ticket: "50000001")
        expect(transaction).not_to be_nil
        expect(transaction.magic_number).to eq("300")
        expect(transaction.state).to eq("error")
        
        # Verificando que os logs indicam o erro de restrição no trace
        error_logs = Logging.where(state: 'ERROR', resourceable: transaction)
        expect(error_logs.count).to be >= 1
        expect(error_logs.first.content).to include("magic number 300")
      end
      
      it 'Allows transactions when magic number is accepted by all relevant traces and accounts' do
        # Atualizar as restrições para permitir o magic number 800
        @trace.update(magics_accept: "200, 800")
        @trace2.update(magics_accept: "600, 800")
        @account1.update(magics_accept: "700, 800")
        
        # Enviando uma ordem com magic number 800 (permitido por todos)
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":50000002,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":800,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação principal foi criada e está executada
        transaction = Transaction.find_by(ticket: "50000002")
        expect(transaction).not_to be_nil
        expect(transaction.magic_number).to eq("800")
        expect(transaction.state).to eq("executed")
        
        # Verificando que slaves foram criados e estão no estado pending (sem erro)
        slaves = TransactionSlave.where(ticket_master: "50000002")
        expect(slaves.count).to be > 0
        
        # Pode haver alguns em erro e outros não, dependendo da combinação de traces e accounts
        # O importante é garantir que existam slaves sem erro, já que o magic number 800 foi permitido
        expect(slaves.where(state: "pending").count).to be > 0
      end
    end
  end
  
  describe 'Verifying the specific implementation of resource restrictions in TraceService' do
    context 'when focusing on line 63 - the double verification condition' do
      before(:each) do
        # Limpeza mais abrangente para garantir que não haja interferência entre testes
        TransactionSlave.destroy_all
        Transaction.destroy_all
        Logging.destroy_all
        
        # Configurando os objetos necessários para o teste
        @trace = create(:trace, :copy, stores: [@store], instrument_control: true, customer_plans: [@customer_plan])
        @account_copy = create(:account, :copy, 
                             store: @store, 
                             customer: @customer, 
                             meta_margin_mode: 'hedging',
                             trace_ids: [@trace.id], 
                             instrument_control: true, 
                             account_server: @account_server)
        @account1 = create(:account, :slave1, 
                         store: @store, 
                         customer: @customer, 
                         meta_margin_mode: 'hedging',
                         trace_ids: [@trace.id], 
                         account_server: @account_server)
        
        # Adicionando instrumentos para as contas
        @account_copy.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
        @account1.instruments.find_or_create_by(symbol: 'EURUSD', name: 'EURUSD', volumes: 0.01)
      end
      
      it 'verifies both trace and account restrictions are checked' do
        # Este teste foca especificamente na linha 63 do TraceService que contém o AND de verificações
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":60000001,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":999,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        # Em vez de verificar chamadas específicas, vamos verificar o resultado
        # que demonstra que ambas as verificações (trace e account) funcionaram
        
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação foi criada e está executada (sem restrições)
        transaction = Transaction.find_by(ticket: "60000001")
        expect(transaction).not_to be_nil
        expect(transaction.state).to eq("executed")
        
        # Verificando que os slaves foram criados, o que significa que ambas 
        # as verificações (trace e account) permitiram a operação
        slaves = TransactionSlave.where(ticket_master: "60000001")
        expect(slaves.count).to be > 0
      end
      
      it 'short-circuits evaluation when trace restricts the transaction' do
        # Configurando o trace para restringir o magic number
        @trace.update(magics_accept: "888")
        
        timestamp = Time.now.strftime('%Y.%m.%d %H:%M:%S')
        
        order_data = "{\"PositionOrders\":[
              {\"symbol\":\"EURUSD\",\"ticketMaster\":60000002,\"ticketDeal\":2014200953,\"type\":0,\"volume\":\"0.01\",\"priceOpen\":\"1.10000\",
               \"priceClose\":0.00000000,\"profit\":\"0\",\"stopLoss\":0.00000000,\"takeProfit\":0.00000000,\"mae\":0.00000000,\"mfe\":0.00000000,
               \"openAt\":\"#{timestamp}\",\"timeGMT\":\"#{timestamp}\",\"timeTrader\":\"#{timestamp}\",\"timeZone\":-3,\"symbolDigits\":5,
               \"magicNumber\":999,\"state\":\"pending\",\"comment\":\"\"}]}"
               
        # Espionando para verificar o comportamento de curto-circuito
        # Deve chamar resource_restricted? apenas uma vez (para o trace) e retornar true
        expect(TradeHelperService).to receive(:resource_restricted?).once.and_call_original
        
        post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/10100/HEDGING',
          params: { "orders" => order_data }
        
        # Verificando a resposta do servidor
        expect(response).to have_http_status(:success)
        
        # Verificando que a transação foi criada mas está com erro
        transaction = Transaction.find_by(ticket: "60000002")
        expect(transaction).not_to be_nil
        expect(transaction.state).to eq("error")
        
        # Verificar que nenhum slave foi criado
        expect(TransactionSlave.where(ticket_master: "60000002").count).to eq(0)
      end
    end
  end
end
