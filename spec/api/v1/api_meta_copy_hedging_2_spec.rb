require 'rails_helper'

RSpec.describe API::V1::APITransactionsCopy do
  before(:context) do
    @store = create(:store)
    @trace = create(:trace, :copy, store: @store)
    @admin = create(:customer, :admin, store:@store)
    @customer = create(:customer, :client, store:@store)
    @account_copy = create(:account, :copy, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account1 = create(:account, :slave1, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @account2 = create(:account, :slave2, store: @store, customer:@customer, meta_margin_mode: 'hedging')
    @ticket_master = 10000001
    
    post '/api/v1/transactions/copy/trasmit/signal_copy/1_42/orders/5647753/HEDGING', 
    params: {"orders"=>"{\"order_id\":483852116,\"open_price\":0.87114000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":1,\"magicnumber\":57392193,\"symbol\":\"EURGBP\",\"comment\":\"57392193\",\"open_at\":1668124835,\"timezone\":-4,\"state_meta\":null}//{\"order_id\":483854383,\"open_price\":1.16938000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395585,\"symbol\":\"GBPUSD\",\"comment\":\"57395585\",\"open_at\":1668130203,\"timezone\":-4,\"state_meta\":null}//{\"order_id\":483854633,\"open_price\":1.16734000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57395828,\"symbol\":\"GBPUSD\",\"comment\":\"57395828\",\"open_at\":1668130644,\"timezone\":-4,\"state_meta\":null}//{\"order_id\":483857785,\"open_price\":1.16541000,\"volume\":0.54000000,\"stop_loss\":0.00000000,\"take_profit\":0.00000000,\"type\":0,\"magicnumber\":57396925,\"symbol\":\"GBPUSD\",\"comment\":\"57396925\",\"open_at\":1668133849,\"timezone\":-4,\"state_meta\":null}", "expert_name"=>"signal_copy", "expert_version"=>"2_00", "action"=>"orders", "account_id"=>"925370", "account_mode"=>"HEDGING"}
  end

  describe API::V1::APITransactionsCopy do
    context 'POST' do

      it 'Hedging - Restrict Magic Number' do
        account = Account.find_by(name: 5634787)
        expect(account.orders.where(content_id:483857785).count).to be == 1

        Account.find_by(name: 5647753).update(magics_accept: 20000)
        account = Account.find_by(name: 5647753)
        order = account.orders.find_by(content_id:483857785)
        transaction = order.transactions.first
        expect(order.state).to be == "executed"
        expect(order.transactions.count).to be == 1
        expect(transaction.state).to be == "executed"
        expect(order.slaves.count).to be == 2
        slave1 = order.slaves.first
        slave2 = order.slaves.last
        expect(slave1.id).to be == 3
        expect(slave2.id).to be == 4
        expect(slave1.state).to be == "pending"
        expect(slave2.state).to be == "pending"
      end

      it 'Hedging - Restrict Magic Number' do
        account = Account.find_by(name: 5634787)
        # @transaction = account.orders.find_by(content_id:483857785).transactions.first
        message = Message::Metatrader.create(content: nil, content_at: Time.zone.now, store: @trace.store, trace:@trace)
        message.update_columns(state: "executed")
        if message.execute
          body "OK|OK|OK"
        else
          content_error = "Message::Metatrader ##{message.try(:id)} cannot executed - Account Name #{account.try(:name)}"
          account.loggings.create(content:content_error, state: "ERROR", changeset: message.try(:errors).try(:full_messages))
        end
        # puts Logging.last.content
        expect(Logging.last.state).to be == "ERROR"

      end
    end
  end
end    