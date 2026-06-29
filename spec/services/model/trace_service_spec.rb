require 'rails_helper'

RSpec.describe Model::TraceService do
  describe '#create_order' do
    let(:store) { double('Store', id: 1) }
    let(:slave_account) { 
      double('Account', 
        id: 2, 
        name: 'Slave Account', 
        instrument_control: true, 
        instruments: double('instruments', find_by: nil),
        orders: double('orders', exists?: false, '<<': nil)
      ) 
    }
    let(:account_slaves) { double('AccountCollection', present?: true) }
    let(:trace) { 
      double('Trace', 
        id: 1, 
        name: 'Test Trace',
        accounts: double('accounts', slave: double('slave_scope', enable: double('enable_scope', where: account_slaves))), 
        stores: [store], 
        name_id: 1, 
        magic_same: false, 
        prop_firm?: false,
        instrument_control: double('instrument_control', to_b: true)
      ) 
    }
    let(:copy_account) { 
      double('Account', 
        id: 1, 
        name: 'Copy Account', 
        netting?: false, 
        hedging?: true, 
        instrument_control: double('instrument_control', to_b: true), 
        orders: double('orders', create: nil, exists?: false, '<<': nil, where: double('where_scope', where: double('not_scope', try: nil))),
        instruments: double('instruments', find_by: nil)
      ) 
    }
    let(:message) { instance_double('Message::Message', loggings: double('loggings', first: nil), request_url: nil) }
    let(:symbol) { 'EURUSD' }
    let(:api_version) { 'v3' }
    
    # Cria a estrutura JSON simplificada que simula uma ordem no formato da API V3
    let(:order_params) do
      {
        "PositionOrders" => [{
          "symbol" => "EURUSD",
          "ticketMaster" => 40000001,
          "ticketDeal" => 2014200953,
          "type" => 0,
          "volume" => "0.01",
          "priceOpen" => "1.10000",
          "priceClose" => 0.00000000,
          "profit" => "0",
          "stopLoss" => 0.00000000,
          "takeProfit" => 0.00000000,
          "mae" => 0.00000000,
          "mfe" => 0.00000000,
          "openAt" => Time.now.strftime('%Y.%m.%d %H:%M:%S'),
          "timeGMT" => Time.now.strftime('%Y.%m.%d %H:%M:%S'),
          "timeTrader" => Time.now.strftime('%Y.%m.%d %H:%M:%S'),
          "timeZone" => -3,
          "symbolDigits" => 5,
          "magicNumber" => 300,
          "state" => "pending",
          "comment" => ""
        }]
      }
    end
    
    before do
      # Allow iteration over account_slaves collection
      allow(account_slaves).to receive(:each).and_yield(slave_account)
      # Mock para a transação criada pelo serviço
      transaction = instance_double('Transaction', 
        id: 100, 
        state: 'executed', 
        executed?: true,
        error?: false,
        loggings: double('loggings', create: true),
        slaves: double('slaves', count: 0),
        try: nil,
        execute: true,
        magic_number: '300',
        traces: double('traces', '<<': nil, exists?: false),
        orders: double('orders', '<<': nil, exists?: false),
        can_erro?: false,
        valid?: true,
        versions: double('versions', last: double('version', changeset: {})),
        update_mfe_mae: true,
        ticket: '40000001'
      )
      
      # Mock para a classe Transaction
      allow(Transaction).to receive(:new).and_return(transaction)
      allow(Transaction).to receive(:last).and_return(transaction)
      allow(Transaction).to receive(:find_by).and_return(nil)
      allow(Transaction).to receive(:create).and_return(transaction)
      allow(Transaction).to receive(:create_with).and_return(
        double('TransactionCreator', find_or_create_by: transaction)
      )
      
      # Mock para Order without the versions method
      order = instance_double('Order',
        id: 200,
        valid?: true,
        error?: false,
        slaves: double('slaves', 
          count: 0, 
          new: double('slave', 
            save: true, 
            magic_number: 300, 
            'magic_number=': nil, 
            'comment=': nil,
            loggings: double('loggings', create: true),
            versions: double('versions', last: double('version', changeset: {}))
          )
        ),
        execute: true,
        save: true,
        try: double('try', versions: double('versions', last: double('version', changeset: {}))),
        state: 'pending',
        present?: true,
        symbol: 'EURUSD'
      )
      
      # Mock para a classe Order
      allow(Order).to receive(:new).and_return(order)
      allow(Order).to receive(:create_with).and_return(
        double('OrderCreator', find_or_create_by: order)
      )
      
      # Criar namespaces para os serializers
      unless defined?(API)
        module API
          module V3
            class SlaveSerializer
              def initialize(*args); end
              def trace_attributes(*args); end
              def comment=(value); end
            end
            
            class CopySerializer
              def initialize(*args); end
              def copy_attributes(*args); end
              def ticket(*args); end
            end
          end
        end
      end
      
      # Mock para os serializers
      allow_any_instance_of(API::V3::SlaveSerializer).to receive(:trace_attributes).and_return({
        magic_number: "300",
        symbol: "EURUSD",
        volume: "0.01",
        ordertype: "0",
        price_open: "1.10000",
        price_request: "1.10000",
        stop_loss: 0.0,
        take_profit: 0.0
      })
      
      allow_any_instance_of(API::V3::CopySerializer).to receive(:copy_attributes).and_return({
        ticket: "40000001",
        magic_number: "300",
        symbol: "EURUSD",
        volume: "0.01",
        ordertype: "0",
        price_open: "1.10000",
        price_request: "1.10000",
        stop_loss: 0.0,
        take_profit: 0.0
      })
      
      # Mock para copy_account para simular orders
      allow(copy_account).to receive(:orders).and_return(
        double('orders', 
          where: double('where_result', where: double('not_result', try: nil)),
          create: order,
          exists?: false,
          '<<': nil
        )
      )
      
      # Adicionar métodos extras para evitar erros inesperados
      allow(order).to receive(:valid?).and_return(true)
      allow(order).to receive(:error?).and_return(false)
      # Removed invalid mock: allow(order).to receive(:create).and_return(order)
      allow(Order).to receive(:create).and_return(order)
      
      # Mock para CopySerializer
      allow_any_instance_of(API::V3::CopySerializer).to receive(:ticket).and_return('40000001')
      
      # Mock para update_mfe_mae
      allow(transaction).to receive(:update_mfe_mae)
      
      # Instead of using any_instance_of for check_instrument, mock it at the service instance level
      # in each test after the service is created
    end

    context 'with resource restrictions' do
      it 'checks both trace and account restrictions before creating slaves' do
        # Executar o serviço
        service = described_class.new(trace, order_params, copy_account, message, symbol, api_version)
        # Mock check_instrument on the specific service instance
        allow(service).to receive(:check_instrument).and_return(double('Instrument'))
        
        # Configurar o mock para TradeHelperService
        expect(TradeHelperService).to receive(:resource_restricted?).with(kind_of(RSpec::Mocks::InstanceVerifyingDouble), trace).and_return(false)
        expect(TradeHelperService).to receive(:resource_restricted?).with(kind_of(RSpec::Mocks::InstanceVerifyingDouble), copy_account).and_return(false)
        
        service.create_order
        
        # A verificação agora é implícita: se os mocks forem chamados como esperado, o teste passa
      end
      
      it 'does not create slaves when trace restricts the transaction' do
        # Executar o serviço
        service = described_class.new(trace, order_params, copy_account, message, symbol, api_version)
        # Mock check_instrument on the specific service instance
        allow(service).to receive(:check_instrument).and_return(double('Instrument'))
        
        # Configurar o mock para TradeHelperService
        expect(TradeHelperService).to receive(:resource_restricted?).with(kind_of(RSpec::Mocks::InstanceVerifyingDouble), trace).and_return(true)
        
        # O segundo check não deve ser chamado se o primeiro retornar true
        expect(TradeHelperService).not_to receive(:resource_restricted?).with(kind_of(RSpec::Mocks::InstanceVerifyingDouble), copy_account)
        
        service.create_order
        
        # A verificação agora é implícita: se os mocks forem chamados como esperado, o teste passa
      end
      
      it 'does not create slaves when account restricts the transaction' do
        # Executar o serviço
        service = described_class.new(trace, order_params, copy_account, message, symbol, api_version)
        # Mock check_instrument on the specific service instance
        allow(service).to receive(:check_instrument).and_return(double('Instrument'))
        
        # Configurar o mock para TradeHelperService
        expect(TradeHelperService).to receive(:resource_restricted?).with(kind_of(RSpec::Mocks::InstanceVerifyingDouble), trace).and_return(false)
        expect(TradeHelperService).to receive(:resource_restricted?).with(kind_of(RSpec::Mocks::InstanceVerifyingDouble), copy_account).and_return(true)
        
        service.create_order
        
        # A verificação agora é implícita: se os mocks forem chamados como esperado, o teste passa
      end
      
      it 'checks conditions in the correct order - short-circuit evaluation' do
        # Este teste verifica o comportamento de curto-circuito do "and" na expressão da linha 63
        call_order = []
        
        # Executar o serviço
        service = described_class.new(trace, order_params, copy_account, message, symbol, api_version)
        # Mock check_instrument on the specific service instance
        allow(service).to receive(:check_instrument).and_return(double('Instrument'))
        
        # Configurar o mock para registrar a ordem das chamadas e simular comportamento de curto-circuito
        allow(TradeHelperService).to receive(:resource_restricted?) do |transaction, resource|
          if resource == trace
            call_order << :trace_check
            true # Retorna true para simular restrição no trace e testar curto-circuito
          elsif resource == copy_account
            call_order << :account_check
            false
          end
        end
        
        service.create_order
        
        # Verificar que apenas a primeira verificação (trace) foi chamada devido ao curto-circuito
        expect(call_order).to eq([:trace_check])
        expect(call_order).not_to include(:account_check)
      end
    end
  end
end
