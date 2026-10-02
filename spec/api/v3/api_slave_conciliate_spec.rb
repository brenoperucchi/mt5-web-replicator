require 'rails_helper'

# Regression for GitHub issue #79: slave conciliation must match the copy by
# ticket_slave (position id) + account, not by symbol. TransactionSlave.symbol
# holds the MASTER symbol, while the slave's history reports the LOCAL broker
# symbol (e.g. XAUUSD on the master, GOLD on the follower broker).
RSpec.describe 'V3 Slave conciliation', type: :request do
  before do
    @plan1         = create(:plan, :plan1)
    @store         = create(:store, plan_id: @plan1.id)
    @plan_method   = create(:payment_method, :stripe)
    @payment       = create(:payment, payment_method: @plan_method, store: @store)
    @customer_plan = create(:customer_plan, payment: @payment, store: @store)
    @trace         = create(:trace, :copy, stores: [@store], customer_plans: [@customer_plan])
    @user_customer = create(:user, :customer, store: @store)
    @customer      = create(:customer, :customer, user: @user_customer)
    @account_server = create(:account_server)
    @account_copy  = create(:account, :copy,   store: @store, customer: @customer, meta_margin_mode: 'hedging', trace_ids: [@trace.id], account_server: @account_server)
    @account_slave = create(:account, :slave1, store: @store, customer: @customer, meta_margin_mode: 'hedging', trace_ids: [@trace.id], account_server: @account_server)

    @master_ticket = 777001
    @slave_ticket  = 888001

    @master = Transaction.create!(ticket: @master_ticket, symbol: 'XAUUSD', ordertype: 0, lot: 0.10,
                                  account: @account_copy, trace: @trace, open_at: Time.zone.parse('2024-04-15 19:00:00'))
    @order  = Order.create!(symbol: 'XAUUSD', content_id: @master_ticket, account: @account_slave, store: @store, trace: @trace, state: 'executed')
    @slave  = TransactionSlave.create!(symbol: 'XAUUSD', ticket_master: @master_ticket, ticket_slave: @slave_ticket, ordertype: 0, lot: 0.10,
                                       account: @account_slave, trace: @trace, store: @store, order: @order, master: @master,
                                       state: 'executed', open_at: Time.zone.parse('2024-04-15 19:00:00'))
  end

  def history_payload(symbol:)
    {
      'ApiSendOrdersHistory' => false,
      'HistoryOrders' => [
        { 'ticketMaster' => @master_ticket, 'ticketSlave' => @slave_ticket, 'ticketDeal' => 1, 'positionID' => @slave_ticket,
          'type' => 0, 'entry' => 1, 'profit' => 12.34, 'priceOpen' => 2300.10, 'priceClose' => 2301.33, 'volume' => 0.10,
          'commission' => -0.50, 'fee' => 0.0, 'swap' => 0.0, 'state' => 'closed', 'symbol' => symbol,
          'comment' => "#{@trace.id}-#{@master_ticket}",
          'openAt' => '2024.04.15 19:00:00', 'closeAt' => '2024.04.15 20:06:29',
          'timeGMT' => '2024.04.15 20:06:29', 'timeTrader' => '2024.04.15 23:06:29' }
      ]
    }.to_json
  end

  def post_history(symbol)
    post "/api/v3/slave/post/orders/imentore_slave/3_00_02/#{@account_server.name}/#{@account_slave.name}/HEDGING",
      params: { orders: history_payload(symbol: symbol) }
  end

  it 'matches the existing copy by ticket and account when the follower broker reports a different symbol' do
    expect { post_history('GOLD') }.not_to change { TransactionSlave.where(account: @account_slave).count }
    expect(response.status).to eq(201)

    @slave.reload
    expect(@slave.state).to eq('closed')
    expect(@slave.profit.to_f).to eq(12.34)
    expect(@slave.fee.to_f).to eq(-0.5)
    expect(@slave.closed_at).to be_present
    expect(@slave.conciliated_at).to be_present
    expect(@slave.symbol).to eq('XAUUSD')
    expect(@slave.symbol_local).to eq('GOLD')
  end

  it 'keeps the same behavior when the reported symbol matches the master symbol' do
    expect { post_history('XAUUSD') }.not_to change { TransactionSlave.where(account: @account_slave).count }

    @slave.reload
    expect(@slave.state).to eq('closed')
    expect(@slave.profit.to_f).to eq(12.34)
    expect(@slave.symbol_local).to be_nil
  end

  it 'does not match a copy with the same ticket on another account' do
    other_slave_account = create(:account, :slave2, store: @store, customer: @customer, meta_margin_mode: 'hedging', trace_ids: [@trace.id], account_server: @account_server)
    @slave.update_columns(account_id: other_slave_account.id)

    post_history('GOLD')

    @slave.reload
    expect(@slave.state).to eq('executed')
    expect(@slave.profit.to_f).to eq(0)
    expect(@slave.symbol_local).to be_nil
  end
end
