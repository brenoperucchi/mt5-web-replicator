require 'rails_helper'

RSpec.describe TradeHelperService do
  describe '.magic_numbers_split' do
    it 'splits magic numbers with various delimiters' do
      expect(described_class.magic_numbers_split('123,456 789')).to eq(['123', '456', '789'])
      expect(described_class.magic_numbers_split('123-456_789.123:456;789')).to eq(['123', '456', '789', '123', '456', '789'])
      expect(described_class.magic_numbers_split("123'456/789")).to eq(['123', '456', '789'])
    end

    it 'removes blank items from the result' do
      expect(described_class.magic_numbers_split('123,,456, ,789')).to eq(['123', '456', '789'])
    end

    it 'returns nil when input is blank or nil' do
      expect(described_class.magic_numbers_split('')).to be_nil
      expect(described_class.magic_numbers_split(nil)).to be_nil
    end
  end

  describe '.magic_number_restricted?' do
    context 'when register has magic number restrictions' do
      let(:register) { double('register', magics_accept: '123,456,789', name: 'Test Register') }

      it 'returns true when magic number is not in the accepted list' do
        expect(described_class.magic_number_restricted?('101', register)).to be true
      end

      it 'returns false when magic number is in the accepted list' do
        expect(described_class.magic_number_restricted?('123', register)).to be false
        expect(described_class.magic_number_restricted?('456', register)).to be false
        expect(described_class.magic_number_restricted?('789', register)).to be false
      end
    end

    context 'when register has no magic number restrictions' do
      it 'returns false when magics_accept is nil' do
        register_without_magics = double('register', magics_accept: nil, name: 'Test Register')
        expect(described_class.magic_number_restricted?('101', register_without_magics)).to be false
      end

      it 'returns false when magics_accept is empty string' do
        register_with_empty_magics = double('register', magics_accept: '', name: 'Test Register')
        expect(described_class.magic_number_restricted?('101', register_with_empty_magics)).to be false
      end
      
      it 'returns false for any magic number when no restrictions exist' do
        register_without_magics = double('register', magics_accept: nil, name: 'Test Register')
        expect(described_class.magic_number_restricted?('123', register_without_magics)).to be false
        expect(described_class.magic_number_restricted?('456', register_without_magics)).to be false
        expect(described_class.magic_number_restricted?('999', register_without_magics)).to be false
      end
    end
  end

  describe '.resource_restricted?' do
    let(:magic_numbers) { '123,456,789' }
    let(:register) { double('register', magics_accept: magic_numbers, name: 'Test Register', name_id: 'TR1', id: 1, class: double('class', name: 'Register')) }
    let(:resource) { double('resource', magic_number: '101', id: 1, class: double('class', name: 'Resource'), loggings: double('loggings'), can_erro?: true, erro: nil, versions: nil, try: nil) }

    before do
      allow(resource.loggings).to receive(:create)
    end

    context 'when register has magic_accept restrictions' do
      it 'returns true and sets error when magic number is restricted' do
        expect(resource).to receive(:erro)
        expect(described_class.resource_restricted?(resource, register)).to be true
      end

      it 'creates a log entry when restriction is found' do
        expect(resource.loggings).to receive(:create).with(hash_including(state: 'ERROR'))
        described_class.resource_restricted?(resource, register)
      end

      it 'returns false when magic number is not restricted' do
        allow(resource).to receive(:magic_number).and_return('123')
        expect(described_class.resource_restricted?(resource, register)).to be false
      end
    end

    context 'when register does not have magic_accept restrictions' do
      it 'returns false without checking restrictions' do
        allow(register).to receive(:magics_accept).and_return('')
        expect(described_class.resource_restricted?(resource, register)).to be false
      end
    end
  end

  describe '.ticketMaster' do
    it 'extracts the ticket master from the resource' do
      resource_with_ticket = double('resource', ticket: '123-456')
      expect(described_class.ticketMaster(resource_with_ticket)).to eq('456')

      resource_with_ticket_master = double('resource', ticket: nil, ticket_master: '789-101')
      expect(described_class.ticketMaster(resource_with_ticket_master)).to eq('101')

      resource_without_dash = double('resource', ticket: '123', ticket_master: nil)
      expect(described_class.ticketMaster(resource_without_dash)).to eq('123')
    end
  end

  describe '.price_open' do
    it 'returns "0" for market orders (type 0 or 1)' do
      resource_market_buy = double('resource', ordertype: '0', price_request: '1.23456')
      expect(described_class.price_open(resource_market_buy)).to eq('0')

      resource_market_sell = double('resource', ordertype: 1, price_request: '1.23456')
      expect(described_class.price_open(resource_market_sell)).to eq('0')
    end

    it 'returns price_request for pending orders (not 0 or 1)' do
      resource_pending = double('resource', ordertype: '2', price_request: '1.23456')
      expect(described_class.price_open(resource_pending)).to eq('1.23456')
    end
  end

  describe '.order_pending?' do
    it 'returns true if content includes STOP or LIMIT' do
      expect(described_class.order_pending?('BUY STOP order')).to be_truthy
      expect(described_class.order_pending?('SELL LIMIT at 1.2345')).to be_truthy
    end

    it 'returns false if content does not include STOP or LIMIT' do
      expect(described_class.order_pending?('BUY order executed')).to be_falsey
    end

    it 'is case insensitive' do
      expect(described_class.order_pending?('buy stop order')).to be_truthy
      expect(described_class.order_pending?('sell limit at 1.2345')).to be_truthy
    end
    
    it 'handles nil or empty content gracefully' do
      expect(described_class.order_pending?(nil)).to be_falsey
          expect(described_class.order_pending?('')).to be_falsey
    end
  end

  describe '.api_request_attributes' do
    let(:resource) do
      double('resource',
        id: 1,
        magic_number: '123',
        ordertype: '0',
        lot: 0.01,
        stop_loss: 0.0,
        take_profit: 0.0,
        state: 'pending',
        symbol: 'EURUSD',
        trace_id: 100,
        comment: 'Test Comment',
        account: double('account', contract_volume: 1000)
      )
    end

    before do
      allow(described_class).to receive(:ticketMaster).with(resource).and_return('456')
      allow(described_class).to receive(:price_open).with(resource).and_return('0')
      allow(resource).to receive(:ticket_slave).and_return(0)
      allow(resource).to receive(:master).and_return(double('master', id: 10, open_at: Time.now))
      allow(resource).to receive(:ticket_deal).and_return(nil)
      allow(resource).to receive(:seconds_ago).and_return(0)
    end

    it 'formats the api request attributes string correctly' do
      result = described_class.api_request_attributes(resource, double('klass'))
      expect(result).to include('0|456|0|100|1|123|10|0|0.01|0.0|0.0|pending|EURUSD|0|0|Test Comment')
    end

    it 'handles nil values gracefully' do
      allow(resource).to receive(:master).and_return(nil)
      expect {
        described_class.api_request_attributes(resource, double('klass'))
      }.not_to raise_error
    end
  end
end
