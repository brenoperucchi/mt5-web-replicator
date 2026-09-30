require 'rails_helper'

# db/seeds.rb with SEED_DEMO=1 (the docker-compose.yml trial default).
# rails_helper truncates before each group and every example runs inside a
# rolled-back transaction, so nothing seeded here leaks into other specs.
RSpec.describe 'Demo seed data (SEED_DEMO=1)' do
  around do |example|
    previous = ENV['SEED_DEMO']
    ENV['SEED_DEMO'] = '1'
    example.run
  ensure
    ENV['SEED_DEMO'] = previous
  end

  def seed!
    expect { Rails.application.load_seed }.to output(/Demo data ready/).to_stdout
  end

  def counts
    {
      users: User.count, customers: Customer.count, customer_plans: CustomerPlan.count,
      traces: Trace.copy.count, accounts: Account.count, orders: Order.count,
      transactions: Transaction.count, slaves: TransactionSlave.count, invoices: Invoice.count,
      invoice_items: InvoiceItem.count, messages: Message::Message.count
    }
  end

  it 'builds a complete demo dataset through the v3 copy/slave message flow' do
    seed!

    demo = User.find_by!(email: 'demo@example.com')
    expect(demo.valid_password?('password123')).to be true
    expect(User.find_by!(email: 'admin@example.com').userable).to be_administrator

    trace = Trace.copy.find_by!(name_id: '20001')
    expect(trace.customer_plans.first).to be_fixed
    expect(trace.instrument_control.to_b).to be false

    copy = Account.copy.find_by!(name: '10100')
    expect(copy.traces).to include(trace)
    expect(Account.slave.where(customer: demo.userable).count).to eq 2

    expect(Transaction.where(trace: trace, account: copy).group(:state).count).to eq('closed' => 10, 'executed' => 3)
    expect(Order.where(trace: trace).group(:state).count).to eq('closed' => 10, 'executed' => 3)
    expect(TransactionSlave.where(trace_id: trace.id).group(:state).count).to eq('closed' => 20, 'executed' => 6)
    expect(Transaction.pluck(:symbol).uniq).to match_array(%w[EURUSD GBPUSD XAUUSD US500])
    expect(Transaction.minimum(:open_at)).to be < 25.days.ago
    expect(TransactionSlave.closed.where(closed_at: nil)).to be_empty

    expect(demo.userable.invoices.group(:state).count).to eq('paid' => 1, 'to_paid' => 1)
    expect(Logging.where(state: 'ERROR')).to be_empty
  end

  it 'is idempotent' do
    seed!
    first = counts
    seed!
    expect(counts).to eq(first)
  end
end
