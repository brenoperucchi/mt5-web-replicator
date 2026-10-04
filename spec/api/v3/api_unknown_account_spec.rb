require 'rails_helper'

# Regression: the v3 copy orders endpoint dereferenced account.store before
# checking the account, raising NoMethodError (500) for unknown accounts.
RSpec.describe 'V3/V2 copy orders with an unknown account', type: :request do
  before { create(:account_server) }

  it 'v3 returns 400 without creating a message' do
    expect {
      post '/api/v3/copy/post/orders/imentore_copy/3_00_02/broker_name/999999999/HEDGING', params: { orders: '{}' }
    }.not_to change { Message::Message.count }
    expect(response.status).to eq(400)
  end

  it 'v2 returns 400 for an unknown account' do
    post '/api/v2/copy/post/orders/imentore_copy/2_30_05/broker_name/999999999/HEDGING', params: { imentore_copy: '{}' }
    expect(response.status).to eq(400)
  end
end
