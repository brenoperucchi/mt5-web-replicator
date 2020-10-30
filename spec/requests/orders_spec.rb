require 'rails_helper'

RSpec.describe Order do
  before(:context) do
    @store = create(:store, master: '5077669')
    @trace = create(:trace, :first, store: @store)
  end

  describe 'Order and transaction' do
    context 'transaction order' do
      it 'transaction should not closed order' do
        @order = create(:order, :m15_trace_first, trace:@trace)
        @order.prepare
        @t1 = create(:transaction, :first, order:@order)
        @t2 = create(:transaction, :second, order:@order)
        @t1.execute
        @t2.execute
        @t2.close
        expect(@order.state).to be == ('executed')
        expect(@order.state).not_to be == ('closed')
      end
      it 'transaction should closed order' do
        @order = create(:order, :m15_trace_first, trace:@trace)
        @order.prepare
        @t1 = create(:transaction, :first, order:@order)
        @t2 = create(:transaction, :second, order:@order)
        @t1.execute
        @t2.execute
        @t1.close
        @t2.close
        expect(@order.state).not_to be == ('executed')
        expect(@order.state).to be == ('closed')
      end
    end
  end
end